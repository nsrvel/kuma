use crate::daemon_state::DaemonStateDb;
use chrono::Utc;
use kuma_domain::StoreError;
use rusqlite::Connection;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct RuntimeProcessStore {
    conn: Arc<Mutex<Connection>>,
}

impl RuntimeProcessStore {
    pub fn new(db: &DaemonStateDb) -> Self {
        Self {
            conn: db.connection(),
        }
    }

    pub fn upsert_running(&self, service_id: &str, pid: u32) -> Result<(), StoreError> {
        let now = Utc::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
        let conn = self.conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "daemon-state lock poisoned".into(),
        })?;
        conn.execute(
            r#"INSERT INTO runtime_process (serviceID, mode, pid, pgid, pidStartTimeMs, executable, argvJSON, composeContextJSON, pollerJSON, startedAt, adopted, intentionalStop, reconnectAttempt, lastFailure, updatedAt)
             VALUES (?1, 'managed', ?2, ?2, 0, '', '[]', NULL, NULL, ?3, 0, 0, NULL, NULL, ?3)
             ON CONFLICT(serviceID) DO UPDATE SET pid = excluded.pid, updatedAt = excluded.updatedAt, intentionalStop = 0"#,
            rusqlite::params![service_id, pid as i64, now],
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        Ok(())
    }

    pub fn clear(&self, service_id: &str) -> Result<(), StoreError> {
        let now = Utc::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
        let conn = self.conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "daemon-state lock poisoned".into(),
        })?;
        conn.execute(
            "UPDATE runtime_process SET pid = NULL, intentionalStop = 1, updatedAt = ?2 WHERE serviceID = ?1",
            rusqlite::params![service_id, now],
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        Ok(())
    }
}
