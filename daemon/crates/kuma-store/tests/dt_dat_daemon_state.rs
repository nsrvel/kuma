//! DT-DAT-29

use kuma_store::{list_user_tables, StoreHandle};

#[test]
fn dt_dat_29_daemon_state_ddl_and_stable_instance_id() {
    let dir = tempfile::tempdir().unwrap();
    let store1 = StoreHandle::open(dir.path()).unwrap();
    let id1 = store1.instance_id().to_string();
    assert_eq!(id1.len(), 36);
    assert_eq!(id1, id1.to_uppercase());

    let daemon_path = dir.path().join("daemon-state.sqlite");
    assert!(daemon_path.exists());
    let conn = rusqlite::Connection::open(&daemon_path).unwrap();
    let tables = list_user_tables(&conn).unwrap();
    assert_eq!(tables.len(), 3);
    for name in ["settings", "runtime_process", "meta"] {
        assert!(tables.contains(&name.to_string()));
    }
    let schema_version: String = conn
        .query_row(
            "SELECT value FROM meta WHERE key = 'schemaVersion'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(schema_version, "1");

    drop(store1);
    let store2 = StoreHandle::open(dir.path()).unwrap();
    assert_eq!(store2.instance_id(), id1);
}
