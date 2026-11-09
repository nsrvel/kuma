use kuma_store::StoreHandle;
use serde_json::json;
use tempfile::TempDir;

#[test]
fn dt_dataport_export_import_roundtrip() {
    let dir = TempDir::new().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let export = store.dataport().export().unwrap();
    let bundle = export.as_object().cloned().unwrap();
    let preview = store.dataport().import_preview(&bundle).unwrap();
    assert!(preview.get("workspaceCount").is_some());
    store.dataport().import(&bundle).unwrap();
}

#[test]
fn dt_dataport_export_all_scope() {
    let dir = TempDir::new().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let export = store.dataport().export().unwrap();
    assert!(export.get("workspaces").is_some());
}

#[test]
fn dt_dataport_factory_reset_keeps_master_key() {
    let dir = TempDir::new().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let _ = store.vault();
    let out = store.dataport().factory_reset().unwrap();
    assert_eq!(out["masterKeyPreserved"], json!(true));
    assert!(dir.path().join("master.key").exists());
}
