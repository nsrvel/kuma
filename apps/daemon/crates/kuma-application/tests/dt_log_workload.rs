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
fn dt_log_workload_tail_wire_shape() {
    let dir = tempfile::tempdir().unwrap();
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let wlist = store.workspace().list().unwrap();
    let ws = wlist[0]["id"].as_str().unwrap();
    let mut create = Map::new();
    create.insert("workspaceID".into(), json!(ws));
    create.insert("name".into(), json!("log-wl"));
    let svc = store.service().create(&create).unwrap();
    let sid = svc["id"].as_str().unwrap();
    let app = Application::new(
        Arc::clone(&store),
        ExecEngine::new(),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000201".into()),
        DataCounts::empty(),
    );
    let req = Request {
        jsonrpc: "2.0".into(),
        method: methods::LOGS_WORKLOAD_TAIL.into(),
        params: json!({ "serviceID": sid, "maxLines": 10 }),
        id: Some(1.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(r) = app.dispatch(req, &mut ctx) else {
        panic!("reply");
    };
    let body = r.result.unwrap();
    assert_eq!(body["serviceID"], sid);
    assert_eq!(body["workload"], true);
    assert!(body.get("text").is_some());
}
