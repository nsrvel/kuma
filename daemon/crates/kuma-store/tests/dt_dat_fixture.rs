//! DT-DAT-05 — opens checked-in 1.x-compatible golden DB without DDL changes.

use kuma_store::{fetch_sqlite_master, StoreHandle};
use std::fs;
use std::path::PathBuf;

const FIXTURE: &str = "tests/fixtures/golden_1x_v8.sqlite";

/// Documented in `tests/fixtures/README.md`.
const EXPECTED_WORKSPACES: u64 = 1;
const EXPECTED_SERVICES: u64 = 1;

fn fixture_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(FIXTURE)
}

#[test]
fn dt_dat_05_golden_fixture_unchanged_by_open() {
    let src = fixture_path();
    assert!(
        src.exists(),
        "missing {FIXTURE}; run `cargo test -p kuma-store write_golden_fixture -- --ignored --exact` once"
    );

    let dir = tempfile::tempdir().unwrap();
    let dest = dir.path().join("kuma.sqlite");
    fs::copy(&src, &dest).unwrap();

    let before_conn = rusqlite::Connection::open(&dest).unwrap();
    let master_before = fetch_sqlite_master(&before_conn).unwrap();
    let migrations_before: Vec<String> = before_conn
        .prepare("SELECT identifier FROM grdb_migrations ORDER BY rowid")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    drop(before_conn);

    let store = StoreHandle::open(dir.path()).unwrap();
    assert_eq!(store.workspace_count().unwrap(), EXPECTED_WORKSPACES);
    assert_eq!(store.service_count().unwrap(), EXPECTED_SERVICES);

    let after_conn = rusqlite::Connection::open(&dest).unwrap();
    let master_after = fetch_sqlite_master(&after_conn).unwrap();
    let migrations_after: Vec<String> = after_conn
        .prepare("SELECT identifier FROM grdb_migrations ORDER BY rowid")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();

    assert_eq!(master_before, master_after);
    assert_eq!(migrations_before, migrations_after);
}

#[test]
#[ignore = "run once locally to refresh golden_1x_v8.sqlite"]
fn write_golden_fixture() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let kuma = store.kuma_connection();
    let conn = kuma.lock().unwrap();
    let ws_id: String = conn
        .query_row("SELECT id FROM workspace LIMIT 1", [], |r| r.get(0))
        .unwrap();
    let now = kuma_store::now_grdb_datetime();
    let svc_id = kuma_store::new_uppercase_uuid();
    conn.execute(
            r#"INSERT INTO service (id, workspaceID, name, isDisabled, isStarred, createdAt, updatedAt)
               VALUES (?1, ?2, 'Golden Service', 0, 0, ?3, ?4)"#,
            rusqlite::params![svc_id, ws_id, now, now],
        )
        .unwrap();
    drop(conn);
    drop(store);

    let out = fixture_path();
    if let Some(parent) = out.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::copy(dir.path().join("kuma.sqlite"), &out).unwrap();
}
