//! DT-SET-29 .. 31 legacy plist import.

use kuma_store::StoreHandle;
use plist::Value as PlistValue;
use rusqlite::OptionalExtension;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

static LEGACY_ITEST: Mutex<()> = Mutex::new(());

fn write_xml_plist(path: &PathBuf, dict: HashMap<String, PlistValue>) {
    let root = PlistValue::Dictionary(dict.into_iter().collect());
    let mut file = fs::File::create(path).unwrap();
    plist::to_writer_xml(&mut file, &root).unwrap();
}

#[test]
fn dt_set_29_imports_known_keys_from_plist() {
    let _guard = LEGACY_ITEST.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let plist_path = dir.path().join("legacy.plist");
    let uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    let mut dict = HashMap::new();
    dict.insert(
        "kuma.settings.autoResumeServices".into(),
        PlistValue::Boolean(true),
    );
    dict.insert(
        "kuma.settings.customDockerPath".into(),
        PlistValue::String("/x/docker".into()),
    );
    dict.insert(
        "kuma.custom_kubectl_path".into(),
        PlistValue::String("/y/kubectl".into()),
    );
    dict.insert(
        "kuma.settings.appearance".into(),
        PlistValue::String("dark".into()),
    );
    dict.insert(
        "kuma.has_completed_onboarding".into(),
        PlistValue::Boolean(true),
    );
    dict.insert(
        "kuma.settings.activeServiceIDsBeforeQuit".into(),
        PlistValue::Array(vec![
            PlistValue::String(uuid.into()),
            PlistValue::String("junk".into()),
        ]),
    );
    dict.insert(
        "NSWindow Frame main".into(),
        PlistValue::String("ignored".into()),
    );
    write_xml_plist(&plist_path, dict);

    std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", plist_path.to_str().unwrap());
    std::env::set_var("KUMA_DATA_DIR", dir.path().join("data").to_str().unwrap());
    let data_dir = dir.path().join("data");
    let store = StoreHandle::open(&data_dir).unwrap();
    let settings = store.settings();
    let list = settings.list(None, false).unwrap();
    let auto = list
        .iter()
        .find(|s| s["key"] == "kuma.settings.autoResumeServices")
        .unwrap();
    assert_eq!(auto["effective"], true);
    let arr = settings
        .get("kuma.settings.activeServiceIDsBeforeQuit")
        .unwrap();
    assert_eq!(arr["effective"][0], uuid.to_uppercase());
    assert_eq!(arr["effective"].as_array().unwrap().len(), 1);

    let ds = store.daemon_state_connection();
    let conn = ds.lock().unwrap();
    let flag: String = conn
        .query_row(
            "SELECT value FROM meta WHERE key = 'legacyImportDone'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert!(!flag.is_empty());
    std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
}

#[test]
fn dt_set_30_legacy_import_idempotent() {
    let _guard = LEGACY_ITEST.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let plist_path = dir.path().join("legacy30.plist");
    let mut dict = HashMap::new();
    dict.insert(
        "kuma.settings.appearance".into(),
        PlistValue::String("dark".into()),
    );
    write_xml_plist(&plist_path, dict);
    std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", plist_path.to_str().unwrap());
    let data_dir = dir.path().join("data");
    let store = StoreHandle::open(&data_dir).unwrap();
    let settings = store.settings();
    assert_eq!(
        settings.get("kuma.settings.appearance").unwrap()["effective"],
        "dark"
    );
    let mut values = serde_json::Map::new();
    values.insert(
        "kuma.settings.appearance".into(),
        serde_json::json!("light"),
    );
    settings.set(&values, false, None).unwrap();
    drop(store);
    fs::write(&plist_path, b"<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>kuma.settings.appearance</key><string>dark</string></dict></plist>").unwrap();
    let store2 = StoreHandle::open(&data_dir).unwrap();
    assert_eq!(
        store2.settings().get("kuma.settings.appearance").unwrap()["effective"],
        "light"
    );
    std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
}

#[test]
fn dt_set_31_corrupt_plist_retries() {
    let _guard = LEGACY_ITEST.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let plist_path = dir.path().join("bad.plist");
    fs::write(
        &plist_path,
        [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30, 0xff, 0xff],
    )
    .unwrap();
    std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", plist_path.to_str().unwrap());
    let data_dir = dir.path().join("data-only-31");
    let store = StoreHandle::open(&data_dir).unwrap();
    let ds = store.daemon_state_connection();
    let conn = ds.lock().unwrap();
    let done: Option<String> = conn
        .query_row(
            "SELECT value FROM meta WHERE key = 'legacyImportDone'",
            [],
            |r| r.get(0),
        )
        .optional()
        .unwrap();
    assert!(done.is_none());
    std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
}
