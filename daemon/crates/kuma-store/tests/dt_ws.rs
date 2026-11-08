use kuma_store::StoreHandle;
use serde_json::json;

#[test]
fn dt_ws_01_default_workspace_list() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let list = store.workspace().list().unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0]["sortOrder"], 0);
    assert_eq!(list[0]["hasImage"], false);
}

#[test]
fn dt_ws_07_cannot_delete_last_workspace() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let id = store.workspace().list().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let err = store.workspace().delete(&id).unwrap_err();
    assert_eq!(err.code(), "KUMA_WS_LAST_WORKSPACE");
}

#[test]
fn dt_ws_03_create_and_delete() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let mut params = serde_json::Map::new();
    params.insert("name".into(), json!("Ops"));
    let ws = store.workspace().create(&params).unwrap();
    let id = ws["id"].as_str().unwrap();
    store.workspace().delete(id).unwrap();
    assert_eq!(store.workspace().list().unwrap().len(), 1);
}
