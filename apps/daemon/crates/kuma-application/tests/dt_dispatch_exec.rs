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
fn dt_dispatch_exec_and_ports() {
    let dir = tempfile::tempdir().unwrap();
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let wlist = store.workspace().list().unwrap();
    let ws = wlist[0]["id"].as_str().unwrap();
    let mut create = Map::new();
    create.insert("workspaceID".into(), json!(ws));
    create.insert("name".into(), json!("exec-dispatch"));
    let svc = store.service().create(&create).unwrap();
    let sid = svc["id"].as_str().unwrap().to_string();
    let app = Application::new(
        Arc::clone(&store),
        ExecEngine::new(),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000302".into()),
        DataCounts::empty(),
    );
    let mut ctx = DispatchContext::unix(ClientKind::Cli);

    let port_req = Request {
        jsonrpc: "2.0".into(),
        method: methods::PORTS_CHECK.into(),
        params: json!({ "localPort": 19999 }),
        id: Some(1.into()),
    };
    let DispatchOutcome::Reply(port) = app.dispatch(port_req, &mut ctx) else {
        panic!("ports");
    };
    assert!(port.result.is_some());

    let adopt_req = Request {
        jsonrpc: "2.0".into(),
        method: methods::RUNTIME_ADOPT_REPORT.into(),
        params: json!({}),
        id: Some(2.into()),
    };
    assert!(matches!(
        app.dispatch(adopt_req, &mut ctx),
        DispatchOutcome::Reply(_)
    ));

    let stat_req = Request {
        jsonrpc: "2.0".into(),
        method: methods::SERVICE_STATUSES.into(),
        params: json!({ "serviceIDs": [sid.clone()] }),
        id: Some(3.into()),
    };
    assert!(matches!(
        app.dispatch(stat_req, &mut ctx),
        DispatchOutcome::Reply(_)
    ));

    let start_all = Request {
        jsonrpc: "2.0".into(),
        method: methods::SERVICE_START_ALL.into(),
        params: json!({ "workspaceID": ws }),
        id: Some(4.into()),
    };
    assert!(matches!(
        app.dispatch(start_all, &mut ctx),
        DispatchOutcome::Reply(_)
    ));
    let stop_all = Request {
        jsonrpc: "2.0".into(),
        method: methods::SERVICE_STOP_ALL.into(),
        params: json!({}),
        id: Some(5.into()),
    };
    assert!(matches!(
        app.dispatch(stop_all, &mut ctx),
        DispatchOutcome::Reply(_)
    ));
}
