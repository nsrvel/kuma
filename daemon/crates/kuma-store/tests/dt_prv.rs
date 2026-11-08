use kuma_store::StoreHandle;
use serde_json::{json, Map};

#[test]
fn dt_prv_13_kubernetes_defaults_kubeconfig_id() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let wss = store.workspace().list().unwrap();
    let wid = wss[0]["id"].as_str().unwrap();
    let mut params: Map<String, serde_json::Value> = Map::new();
    params.insert("name".into(), json!("k8s-svc"));
    params.insert("workspaceID".into(), json!(wid));
    params.insert(
        "provider".into(),
        json!({ "type": "kubernetes", "label": "k8s" }),
    );
    let svc = store.service().create(&params).unwrap();
    let providers = store.provider().list(svc["id"].as_str().unwrap()).unwrap();
    let p = &providers["providers"][0];
    assert_eq!(
        p["kubeConfigID"],
        json!(kuma_store::kubeconfig::DEFAULT_ID)
    );
}
