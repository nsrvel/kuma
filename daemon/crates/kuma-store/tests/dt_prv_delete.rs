use kuma_store::StoreHandle;
use serde_json::{json, Map};

#[test]
fn dt_prv_delete_and_active_promotion() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let wlist = store.workspace().list().unwrap();
    let ws = wlist[0]["id"].as_str().unwrap();
    let mut create = Map::new();
    create.insert("workspaceID".into(), json!(ws));
    create.insert("name".into(), json!("del"));
    let svc = store.service().create(&create).unwrap();
    let sid = svc["id"].as_str().unwrap();
    let plist0 = store.provider().list(sid).unwrap();
    let p0 = plist0["providers"][0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let mut add = Map::new();
    add.insert("serviceID".into(), json!(sid));
    add.insert(
        "provider".into(),
        json!({"type": "shell", "label": "b", "runCommand": "echo b"}),
    );
    let added = store.provider().add(&add).unwrap();
    let p1 = added["provider"]["id"].as_str().unwrap().to_string();
    let mut del = Map::new();
    del.insert("id".into(), json!(p0));
    let out = store.provider().delete(&del).unwrap();
    assert_eq!(out["deleted"], true);
    assert_eq!(out["activeProviderID"], p1);
    let mut del_last = Map::new();
    del_last.insert("id".into(), json!(p1));
    assert!(store.provider().delete(&del_last).is_err());
}
