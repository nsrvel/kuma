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
    assert_eq!(p["kubeConfigID"], json!(kuma_store::kubeconfig::DEFAULT_ID));
}

#[test]
fn dt_prv_18_ssh_host_rejected_on_shell_provider() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let wss = store.workspace().list().unwrap();
    let wid = wss[0]["id"].as_str().unwrap().to_string();
    let mut params: Map<String, serde_json::Value> = Map::new();
    params.insert("name".into(), json!("foreign-field"));
    params.insert("workspaceID".into(), json!(wid));
    let svc = store.service().create(&params).unwrap();
    let sid = svc["id"].as_str().unwrap();
    let plist = store.provider().list(sid).unwrap();
    let pid = plist["providers"][0]["id"].as_str().unwrap().to_string();
    store
        .provider()
        .update(
            store.vault(),
            &serde_json::from_value(json!({
                "id": pid,
                "type": "shell",
                "runCommand": "echo ok",
            }))
            .unwrap(),
        )
        .unwrap();
    let err = store
        .provider()
        .update(
            store.vault(),
            &serde_json::from_value(json!({ "id": pid, "sshHost": "10.0.0.1" })).unwrap(),
        )
        .unwrap_err();
    assert!(err.message().contains("KUMA_PRV_FIELD_NOT_APPLICABLE"));
}
