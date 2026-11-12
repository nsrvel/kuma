use kuma_domain::StoreError;
use rusqlite::Connection;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn backup_before_migrate(
    db_path: &Path,
    data_dir: &Path,
) -> Result<Option<PathBuf>, StoreError> {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let dest = data_dir.join(format!("kuma.sqlite.pre-migrate-{ts}.bak"));
    vacuum_into(db_path, &dest)?;
    Ok(Some(dest))
}

pub fn maybe_pre_daemon_backup(db_path: &Path, data_dir: &Path) -> Result<(), StoreError> {
    let dest = data_dir.join("kuma.sqlite.pre-daemon.bak");
    if dest.exists() {
        return Ok(());
    }
    if !db_path.exists() {
        return Ok(());
    }
    let conn = Connection::open(db_path).map_err(|e| StoreError::BackupFailed {
        detail: e.to_string(),
    })?;
    let workspaces: i64 = conn
        .query_row("SELECT COUNT(*) FROM workspace", [], |r| r.get(0))
        .unwrap_or(0);
    if workspaces == 0 {
        return Ok(());
    }
    vacuum_into(db_path, &dest)
}

fn vacuum_into(source: &Path, dest: &Path) -> Result<(), StoreError> {
    if dest.exists() {
        std::fs::remove_file(dest).map_err(|e| StoreError::BackupFailed {
            detail: e.to_string(),
        })?;
    }
    let conn = Connection::open(source).map_err(|e| StoreError::BackupFailed {
        detail: e.to_string(),
    })?;
    let dest_str = dest.to_string_lossy();
    conn.execute_batch(&format!("VACUUM INTO '{}';", dest_str.replace('\'', "''")))
        .map_err(|e| StoreError::BackupFailed {
            detail: e.to_string(),
        })?;
    Ok(())
}
