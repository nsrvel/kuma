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

    pub fn mark_intentional_stop(&self, service_id: &str) -> Result<(), StoreError> {
        let now = Utc::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
        let conn = self.conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "daemon-state lock poisoned".into(),
        })?;
        conn.execute(
            "UPDATE runtime_process SET intentionalStop = 1, updatedAt = ?2 WHERE serviceID = ?1",
            rusqlite::params![service_id, now],
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        Ok(())
    }

    pub fn delete_row(&self, service_id: &str) -> Result<(), StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "daemon-state lock poisoned".into(),
        })?;
        conn.execute(
            "DELETE FROM runtime_process WHERE serviceID = ?1",
            [service_id],
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        Ok(())
    }

    /// Rows with a stored pid and no intentional stop — verified alive for adopt report.
    pub fn adopt_candidates(&self) -> Result<Vec<(String, u32)>, StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "daemon-state lock poisoned".into(),
        })?;
        let mut stmt = conn
            .prepare(
                "SELECT serviceID, pid FROM runtime_process WHERE pid IS NOT NULL AND intentionalStop = 0",
            )
            .map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        let rows = stmt
            .query_map([], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)? as u32))
            })
            .map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
        let mut out = Vec::new();
        for row in rows {
            let (sid, pid) = row.map_err(|e| StoreError::DbOpenFailed {
                detail: e.to_string(),
            })?;
            if pid_alive(pid) {
                out.push((sid, pid));
            }
        }
        Ok(out)
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

#[cfg(unix)]
fn pid_alive(pid: u32) -> bool {
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

#[cfg(not(unix))]
fn pid_alive(_pid: u32) -> bool {
    false
}
