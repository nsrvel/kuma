//! DT-DAT-06 .. 08

use kuma_domain::StoreError;
use kuma_store::{
    apply_through, is_sqlite_file, open_kuma_connection, read_applied_identifiers, StoreHandle,
};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

fn file_sha256(path: &Path) -> Vec<u8> {
    let bytes = fs::read(path).unwrap();
    Sha256::digest(bytes).to_vec()
}

#[test]
fn dt_dat_06_pending_v3_through_v8_and_backup() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("kuma.sqlite");
    let conn = open_kuma_connection(&db_path).unwrap();
    apply_through(&conn, 1).unwrap();
    assert_eq!(read_applied_identifiers(&conn).unwrap().len(), 2);

    drop(conn);
    let store = StoreHandle::open(dir.path()).unwrap();

    let backups: Vec<_> = fs::read_dir(dir.path())
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|s| s.starts_with("kuma.sqlite.pre-migrate-"))
                .unwrap_or(false)
        })
        .collect();
    assert_eq!(backups.len(), 1);
    assert!(is_sqlite_file(&backups[0]));

    assert_eq!(store.schema_migrations().len(), 8);
}

#[test]
fn dt_dat_07_unknown_migration_refused() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    drop(store);
    let conn = rusqlite::Connection::open(dir.path().join("kuma.sqlite")).unwrap();
    conn.execute(
        "INSERT INTO grdb_migrations (identifier) VALUES ('v9_future')",
        [],
    )
    .unwrap();
    drop(conn);

    let before = file_sha256(&dir.path().join("kuma.sqlite"));
    let err = match StoreHandle::open(dir.path()) {
        Err(e) => e,
        Ok(_) => panic!("expected error"),
    };
    assert!(matches!(err, StoreError::SchemaTooNew { .. }));
    assert_eq!(err.code(), "KUMA_DAT_SCHEMA_TOO_NEW");
    let after = file_sha256(&dir.path().join("kuma.sqlite"));
    assert_eq!(before, after);
}

#[test]
fn dt_dat_08_garbage_file_not_modified() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("kuma.sqlite");
    fs::write(&path, b"not a sqlite database file!!!").unwrap();
    let before = fs::read(&path).unwrap();
    let err = match StoreHandle::open(dir.path()) {
        Err(e) => e,
        Ok(_) => panic!("expected error"),
    };
    assert!(matches!(err, StoreError::DbOpenFailed { .. }));
    assert_eq!(fs::read(&path).unwrap(), before);
}
