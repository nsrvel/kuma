use kuma_store::StoreHandle;
use serde_json::json;

#[test]
fn dt_svc_create_lists_in_workspace() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let ws = store.workspace().list().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let mut create = serde_json::Map::new();
    create.insert("workspaceID".into(), json!(ws));
    create.insert("name".into(), json!("API"));
    let svc = store.service().create(&create).unwrap();
    let sid = svc["id"].as_str().unwrap();
    let mut list_params = serde_json::Map::new();
    list_params.insert("workspaceID".into(), json!(ws));
    let deck = store.service().list(&list_params).unwrap();
    assert_eq!(deck["totalCount"], 1);
    assert_eq!(deck["items"][0]["id"], json!(sid));
    let providers = store.provider().list(sid).unwrap();
    assert_eq!(providers["providers"].as_array().unwrap().len(), 1);
}
