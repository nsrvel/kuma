use kuma_application::{
    Application, ClientKind, DataCounts, DispatchContext, DispatchOutcome, LifecycleState,
};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Request;
use kuma_protocol::methods;
use kuma_store::StoreHandle;
use std::sync::Arc;
use tempfile::TempDir;

#[test]
fn dt_sec_audit_settings_set_writes_line() {
    let dir = TempDir::new().unwrap();
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let app = Application::new(
        Arc::clone(&store),
        ExecEngine::new(),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000001".into()),
        DataCounts::empty(),
    );
    let req = Request {
        jsonrpc: "2.0".into(),
        method: methods::WORKSPACE_CREATE.into(),
        params: serde_json::json!({ "name": "Audit Trail WS" }),
        id: Some(1.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
        panic!("reply");
    };
    assert!(resp.result.is_some());
    let log = std::fs::read_to_string(dir.path().join("audit.log")).unwrap();
    assert!(log.contains("workspace.create"));
}
