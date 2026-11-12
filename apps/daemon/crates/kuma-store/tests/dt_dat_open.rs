//! DT-DAT-01 .. 04

use kuma_store::{
    assert_expected_schema, fetch_sqlite_master, foreign_keys_enabled, journal_mode, StoreHandle,
    KNOWN_MIGRATION_IDENTIFIERS,
};

fn open_empty_dir() -> (tempfile::TempDir, StoreHandle) {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    (dir, store)
}

#[test]
fn dt_dat_01_wal_and_foreign_keys() {
    let (dir, store) = open_empty_dir();
    assert!(dir.path().join("kuma.sqlite").exists());
    let kuma = store.kuma_connection();
    let conn = kuma.lock().unwrap();
    assert_eq!(journal_mode(&conn).unwrap().to_lowercase(), "wal");
    assert!(foreign_keys_enabled(&conn).unwrap());
}

#[test]
fn dt_dat_02_eight_migrations_in_order() {
    let (_, store) = open_empty_dir();
    let applied = store.schema_migrations();
    assert_eq!(applied.len(), 8);
    for (i, id) in KNOWN_MIGRATION_IDENTIFIERS.iter().enumerate() {
        assert_eq!(&applied[i], id);
    }
}

#[test]
fn dt_dat_03_sqlite_master_matches_spec() {
    let (_, store) = open_empty_dir();
    let kuma = store.kuma_connection();
    let conn = kuma.lock().unwrap();
    assert_expected_schema(&conn).unwrap();
}

#[test]
fn dt_dat_04_default_workspace_seed() {
    let (_, store) = open_empty_dir();
    assert_eq!(store.workspace_count().unwrap(), 1);
    let kuma = store.kuma_connection();
    let conn = kuma.lock().unwrap();
    let (id, name, image, sort, created, updated): (
        String,
        String,
        Option<String>,
        i64,
        String,
        String,
    ) = conn
        .query_row(
            "SELECT id, name, imagePath, sortOrder, createdAt, updatedAt FROM workspace",
            [],
            |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                ))
            },
        )
        .unwrap();
    assert_eq!(id.len(), 36);
    assert_eq!(id, id.to_uppercase());
    assert!(name.ends_with("'s Space"));
    assert!(image.is_none());
    assert_eq!(sort, 0);
    for ts in [&created, &updated] {
        assert!(ts.chars().all(|c| c.is_ascii_digit()
            || c == '-'
            || c == ' '
            || c == ':'
            || c == '.'));
    }
}

#[test]
fn dt_dat_03_dump_on_mismatch() {
    let (_, store) = open_empty_dir();
    let kuma = store.kuma_connection();
    let conn = kuma.lock().unwrap();
    if assert_expected_schema(&conn).is_err() {
        let live = fetch_sqlite_master(&conn).unwrap();
        for row in live {
            eprintln!("{row:?}");
        }
        panic!("schema mismatch");
    }
}
