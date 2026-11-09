use crate::settings::change::SettingsChangeSink;
use crate::settings::effective::read_stored;
use crate::settings::registry::RESET_KEYS;
use kuma_domain::SettingsError;
use rusqlite::Connection;

pub struct ResetResult {
    pub removed: Vec<String>,
    pub keys: Vec<String>,
}

pub fn reset_settings(
    conn: &mut Connection,
    sink: &dyn SettingsChangeSink,
) -> Result<ResetResult, SettingsError> {
    let keys: Vec<String> = RESET_KEYS.iter().map(|s| (*s).to_string()).collect();
    let mut removed = Vec::new();
    for key in &keys {
        if read_stored(conn, key)?.is_some() {
            removed.push(key.clone());
        }
    }

    let tx = conn
        .transaction()
        .map_err(|e| SettingsError::InvalidValue {
            key: "transaction".into(),
            message: e.to_string(),
        })?;
    for key in &keys {
        tx.execute("DELETE FROM settings WHERE key = ?1", [key.as_str()])
            .map_err(|e| SettingsError::InvalidValue {
                key: key.clone(),
                message: e.to_string(),
            })?;
    }
    tx.commit().map_err(|e| SettingsError::InvalidValue {
        key: "commit".into(),
        message: e.to_string(),
    })?;

    let _ = sink;

    Ok(ResetResult { removed, keys })
}
