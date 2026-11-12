use crate::seed::new_uppercase_uuid;
use kuma_domain::StoreError;
use rusqlite::{Connection, OptionalExtension};
use std::path::Path;
use std::sync::{Arc, Mutex};

const META_SCHEMA_VERSION: &str = "1";
const META_INSTANCE_ID: &str = "instanceId";

pub struct DaemonStateDb {
    conn: Arc<Mutex<Connection>>,
    instance_id: String,
}

impl DaemonStateDb {
    pub fn open(path: &Path) -> Result<Self, StoreError> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        }
        let conn = Connection::open(path).map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        conn.busy_timeout(std::time::Duration::from_millis(5000))
            .map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            .map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        Self::ensure_schema(&conn)?;
        let instance_id = Self::load_or_create_instance_id(&conn)?;
        let conn = Arc::new(Mutex::new(conn));
        Ok(Self { conn, instance_id })
    }

    pub fn connection(&self) -> Arc<Mutex<Connection>> {
        Arc::clone(&self.conn)
    }

    pub fn instance_id(&self) -> &str {
        &self.instance_id
    }

    fn ensure_schema(conn: &Connection) -> Result<(), StoreError> {
        conn.execute_batch(
            r#"
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updatedAt TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS runtime_process (serviceID TEXT PRIMARY KEY, mode TEXT NOT NULL, pid INTEGER, pgid INTEGER, pidStartTimeMs INTEGER, executable TEXT, argvJSON TEXT, composeContextJSON TEXT, pollerJSON TEXT, startedAt TEXT NOT NULL, adopted INTEGER NOT NULL DEFAULT 0, intentionalStop INTEGER NOT NULL DEFAULT 0, reconnectAttempt INTEGER, lastFailure TEXT, updatedAt TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"#,
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        let schema_version: Option<String> = conn
            .query_row(
                "SELECT value FROM meta WHERE key = 'schemaVersion'",
                [],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        match schema_version.as_deref() {
            None => {
                conn.execute(
                    "INSERT INTO meta (key, value) VALUES ('schemaVersion', ?1)",
                    [META_SCHEMA_VERSION],
                )
                .map_err(|e| StoreError::DbOpenFailed {
                    detail: e.to_string(),
                })?;
            }
            Some(v) if v == META_SCHEMA_VERSION => {}
            Some(v) => {
                return Err(StoreError::SchemaTooNew {
                    identifier: format!("daemon-state schemaVersion={v}"),
                });
            }
        }
        Ok(())
    }

    fn load_or_create_instance_id(conn: &Connection) -> Result<String, StoreError> {
        let existing: Option<String> = conn
            .query_row(
                "SELECT value FROM meta WHERE key = ?1",
                [META_INSTANCE_ID],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        if let Some(id) = existing {
            return Ok(id);
        }
        let id = new_uppercase_uuid();
        conn.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2)",
            rusqlite::params![META_INSTANCE_ID, id],
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        Ok(id)
    }
}

pub fn list_user_tables(conn: &Connection) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn
        .prepare(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    let rows = stmt
        .query_map([], |r| r.get(0))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    let mut names = Vec::new();
    for row in rows {
        names.push(row.map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?);
    }
    Ok(names)
}
