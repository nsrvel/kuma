use kuma_application::{Application, ClientKind, DispatchContext, DispatchOutcome};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Request;
use kuma_protocol::methods;
use kuma_store::StoreHandle;
use std::sync::Arc;

#[test]
fn dt_sec_rotate_bumps_rest_epoch() {
    let dir = tempfile::tempdir().unwrap();
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let app = Application::new(
        store,
        ExecEngine::new(),
        Arc::new(|| {}),
        kuma_application::LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000001".into()),
        kuma_application::DataCounts::empty(),
    );
    let before = app.rest_token_epoch();
    let req = Request {
        jsonrpc: "2.0".into(),
        method: methods::DAEMON_ROTATE_API_TOKEN.into(),
        params: serde_json::json!({}),
        id: Some(1.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
        panic!("expected reply");
    };
    assert!(resp.error.is_none());
    assert!(app.rest_token_epoch() > before);
}
