use kuma_application::{
    Application, ClientKind, DataCounts, DispatchContext, DispatchOutcome, LifecycleState,
};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Request;
use kuma_protocol::methods;
use kuma_store::kubeconfig::DEFAULT_ID;
use kuma_store::StoreHandle;
use serde_json::json;
use std::fs;
use std::io::Write;
use std::sync::Arc;

fn mock_kubectl(dir: &tempfile::TempDir) -> String {
    let path = dir.path().join("mock-kubectl.sh");
    let mut f = fs::File::create(&path).unwrap();
    writeln!(
        f,
        r#"#!/bin/sh
if [ "$1" = "get" ] && [ "$2" = "ns" ]; then
  echo '{{"items":[{{"metadata":{{"name":"default"}}}}]}}'
  exit 0
fi
if [ "$1" = "get" ] && [ "$2" = "all" ]; then
  echo '{{"items":[]}}'
  exit 0
fi
exit 1
"#
    )
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    path.display().to_string()
}

#[test]
fn dt_k8s_namespaces_resources_fixture() {
    let dir = tempfile::tempdir().unwrap();
    std::env::set_var("KUMA_KUBECTL_BIN", mock_kubectl(&dir));
    let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
    let app = Application::new(
        Arc::clone(&store),
        ExecEngine::new(),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000301".into()),
        DataCounts::empty(),
    );
    let ns_req = Request {
        jsonrpc: "2.0".into(),
        method: methods::K8S_NAMESPACES.into(),
        params: json!({ "kubeConfigID": DEFAULT_ID }),
        id: Some(1.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(ns) = app.dispatch(ns_req, &mut ctx) else {
        panic!("namespaces");
    };
    let ns_body = ns.result.unwrap();
    let items = ns_body["namespaces"].as_array().unwrap();
    assert!(!items.is_empty());
    let res_req = Request {
        jsonrpc: "2.0".into(),
        method: methods::K8S_RESOURCES.into(),
        params: json!({ "kubeConfigID": DEFAULT_ID, "namespace": "default" }),
        id: Some(2.into()),
    };
    let DispatchOutcome::Reply(res) = app.dispatch(res_req, &mut ctx) else {
        panic!("resources");
    };
    assert!(res.result.unwrap().get("resources").is_some());
    std::env::remove_var("KUMA_KUBECTL_BIN");
}
