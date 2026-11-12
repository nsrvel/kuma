use kuma_store::StoreHandle;
use serde_json::json;

#[test]
fn dt_grp_01_create_default_name() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let ws = store.workspace().list().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let mut params = serde_json::Map::new();
    params.insert("workspaceID".into(), json!(ws));
    let group = store.group().create(&params).unwrap();
    assert_eq!(group["name"], "New Group");
    assert_eq!(group["sortOrder"], 1);
}
