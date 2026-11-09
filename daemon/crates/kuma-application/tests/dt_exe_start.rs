//! Exec path through application dispatch (runner + store).

use kuma_application::{
    Application, ClientKind, DataCounts, DispatchContext, DispatchOutcome, LifecycleState,
};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Request;
use kuma_protocol::methods;
use kuma_store::StoreHandle;
use serde_json::{json, Map};
use std::sync::Arc;

#[test]
fn dt_exe_start_stop_shell_via_dispatch() {
    let dir = tempfile::tempdir().unwrap();
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let ws = store.workspace().list().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let mut create = Map::new();
    create.insert("workspaceID".into(), json!(ws));
    create.insert("name".into(), json!("exe-via-dispatch"));
    let svc = store.service().create(&create).unwrap();
    let sid = svc["id"].as_str().unwrap();
    let plist = store.provider().list(sid).unwrap();
    let pid = plist["providers"][0]["id"].as_str().unwrap();
    let mut p = Map::new();
    p.insert("id".into(), json!(pid));
    p.insert("type".into(), json!("shell"));
    p.insert("runCommand".into(), json!("sleep 30"));
    store.provider().update(store.vault(), &p).unwrap();

    let app = Application::new(
        Arc::clone(&store),
        ExecEngine::new(),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000101".into()),
        DataCounts::empty(),
    );

    let start = Request {
        jsonrpc: "2.0".into(),
        method: methods::SERVICE_START.into(),
        params: json!({ "id": sid }),
        id: Some(1.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    assert!(matches!(
        app.dispatch(start, &mut ctx),
        DispatchOutcome::Reply(_)
    ));

    let status = Request {
        jsonrpc: "2.0".into(),
        method: methods::SERVICE_STATUS.into(),
        params: json!({ "id": sid }),
        id: Some(2.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(resp) = app.dispatch(status, &mut ctx) else {
        panic!("status reply");
    };
    assert!(resp.result.is_some());

    let stop = Request {
        jsonrpc: "2.0".into(),
        method: methods::SERVICE_STOP.into(),
        params: json!({ "id": sid }),
        id: Some(3.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    assert!(matches!(
        app.dispatch(stop, &mut ctx),
        DispatchOutcome::Reply(_)
    ));
}
