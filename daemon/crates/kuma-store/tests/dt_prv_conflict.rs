use kuma_store::StoreHandle;
use serde_json::{json, Map};

#[test]
fn dt_prv_19_compose_yaml_conflict_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let wid = store.workspace().list().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let mut params: Map<String, serde_json::Value> = Map::new();
    params.insert("name".into(), json!("compose"));
    params.insert("workspaceID".into(), json!(wid));
    let svc = store.service().create(&params).unwrap();
    let sid = svc["id"].as_str().unwrap();
    let pid = store.provider().list(sid).unwrap()["providers"][0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let err = store
        .provider()
        .update(
            store.vault(),
            &serde_json::from_value(json!({
                "id": pid,
                "composeFilePath": "/tmp/a.yml",
                "yamlConfig": "x: 1",
            }))
            .unwrap(),
        )
        .unwrap_err();
    assert!(err.message().contains("KUMA_PRV_SOURCE_CONFLICT"));
}
