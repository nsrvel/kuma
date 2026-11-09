use kuma_domain::StoreError;
use rusqlite::Connection;
use std::fs;
use std::path::Path;

pub fn is_sqlite_file(path: &Path) -> bool {
    let Ok(meta) = fs::metadata(path) else {
        return false;
    };
    if meta.len() < 16 {
        return false;
    }
    let Ok(bytes) = fs::read(path) else {
        return false;
    };
    bytes.starts_with(b"SQLite format 3")
}

pub fn open_kuma_connection(path: &Path) -> Result<Connection, StoreError> {
    if path.exists() && !is_sqlite_file(path) {
        return Err(StoreError::DbOpenFailed {
            detail: "file is not a SQLite database".into(),
        });
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    }
    let conn = Connection::open(path).map_err(|e| {
        if e.sqlite_error_code() == Some(rusqlite::ErrorCode::DatabaseBusy) {
            StoreError::DbBusy
        } else {
            StoreError::DbOpenFailed {
                detail: e.to_string(),
            }
        }
    })?;
    configure_connection(&conn)?;
    Ok(conn)
}

pub fn configure_connection(conn: &Connection) -> Result<(), StoreError> {
    conn.busy_timeout(std::time::Duration::from_millis(5000))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    let journal: String = conn
        .query_row("PRAGMA journal_mode=WAL", [], |r| r.get(0))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    if !journal.eq_ignore_ascii_case("wal") {
        return Err(StoreError::DbOpenFailed {
            detail: format!("expected WAL journal_mode, got {journal}"),
        });
    }
    conn.execute_batch("PRAGMA foreign_keys=ON;")
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(())
}

pub fn foreign_keys_enabled(conn: &Connection) -> Result<bool, StoreError> {
    let on: i64 = conn
        .query_row("PRAGMA foreign_keys", [], |r| r.get(0))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(on != 0)
}

pub fn journal_mode(conn: &Connection) -> Result<String, StoreError> {
    conn.query_row("PRAGMA journal_mode", [], |r| r.get(0))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })
}

pub fn table_count(conn: &Connection, table: &str) -> Result<u64, StoreError> {
    let sql = format!("SELECT COUNT(*) FROM {table}");
    conn.query_row(&sql, [], |r| r.get::<_, i64>(0))
        .map(|n| n as u64)
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })
}
