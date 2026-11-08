use kuma_application::{
    Application, ClientKind, DataCounts, DispatchContext, DispatchOutcome, LifecycleState,
};
use kuma_exec::{start_service, stop_service, ExecEngine};
use kuma_protocol::jsonrpc::Request;
use kuma_protocol::methods;
use kuma_store::StoreHandle;
use std::sync::Arc;
use tempfile::TempDir;

#[test]
fn dt_prv_locked_while_shell_running() {
    let dir = TempDir::new().unwrap();
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let wid = store
        .workspace()
        .list()
        .unwrap()
        .first()
        .and_then(|w| w.get("id"))
        .and_then(|v| v.as_str())
        .unwrap()
        .to_string();
    let svc = store
        .service()
        .create(
            &serde_json::from_value(serde_json::json!({
                "workspaceID": wid,
                "name": "lock-test",
            }))
            .unwrap(),
        )
        .unwrap();
    let sid = svc.get("id").and_then(|v| v.as_str()).unwrap();
    let plist = store.provider().list(sid).unwrap();
    let pid = plist["providers"][0]["id"].as_str().unwrap();
    store
        .provider()
        .update(
            store.vault(),
            &serde_json::from_value(serde_json::json!({
                "id": pid,
                "type": "shell",
                "runCommand": "sleep 30",
            }))
            .unwrap(),
        )
        .unwrap();
    let exec = ExecEngine::new();
    let provider = store.provider().get_for_exec(pid, store.vault()).unwrap();
    let exec = Arc::new(exec);
    start_service(&exec, sid, &provider).unwrap();
    let app = Application::new(
        store,
        Arc::clone(&exec),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000002".into()),
        DataCounts::empty(),
    );
    let req = Request {
        jsonrpc: "2.0".into(),
        method: methods::PROVIDER_UPDATE.into(),
        params: serde_json::json!({ "id": pid, "label": "blocked" }),
        id: Some(9.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
        panic!("reply");
    };
    assert!(resp.error.is_some());
    assert!(resp
        .error
        .as_ref()
        .unwrap()
        .message
        .contains("read-only while active"));
    let _ = stop_service(&exec, sid);
}
