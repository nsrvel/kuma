mod change;
mod effective;
mod registry;
mod reset;
mod time;
mod validate;
mod write;

pub use change::{ChangeEvent, RecordingChangeSink, SettingsChangeSink};
pub use effective::{effective_for, read_stored};
pub use registry::{lookup, KeyKind, KeyDef, REGISTRY, RESET_KEYS};
pub use validate::{expand_tilde, validate_custom_binary};
pub use time::now_wire_timestamp;
use effective::build_setting_for_key;
use kuma_domain::SettingsError;
use reset::{reset_settings, ResetResult};
use rusqlite::Connection;
use serde_json::{Map, Value};
use std::sync::{Arc, Mutex};
use write::{list_all_settings, set_values, SetResult};

#[derive(Clone)]
pub struct SettingsStore {
    conn: Arc<Mutex<Connection>>,
    sink: Arc<dyn SettingsChangeSink>,
}

impl SettingsStore {
    pub fn new(conn: Arc<Mutex<Connection>>, sink: Arc<dyn SettingsChangeSink>) -> Self {
        Self { conn, sink }
    }

    pub fn with_recording_sink(
        conn: Arc<Mutex<Connection>>,
    ) -> (Self, Arc<Mutex<Vec<change::ChangeEvent>>>) {
        let (rec, events) = RecordingChangeSink::new();
        (
            Self::new(conn, Arc::new(rec)),
            events,
        )
    }

    fn with_conn<R>(&self, f: impl FnOnce(&Connection) -> Result<R, SettingsError>) -> Result<R, SettingsError> {
        let guard = self.conn.lock().map_err(|_| SettingsError::InvalidValue {
            key: "lock".into(),
            message: "daemon-state lock poisoned".into(),
        })?;
        f(&guard)
    }

    fn with_conn_mut<R>(
        &self,
        f: impl FnOnce(&mut Connection) -> Result<R, SettingsError>,
    ) -> Result<R, SettingsError> {
        let mut guard = self.conn.lock().map_err(|_| SettingsError::InvalidValue {
            key: "lock".into(),
            message: "daemon-state lock poisoned".into(),
        })?;
        f(&mut guard)
    }

    pub fn list(
        &self,
        prefix: Option<&str>,
        include_client: bool,
    ) -> Result<Vec<Value>, SettingsError> {
        self.with_conn(|conn| list_all_settings(conn, prefix, include_client))
    }

    pub fn get(&self, key: &str) -> Result<Value, SettingsError> {
        if key.starts_with("client.") {
            return self.with_conn(|conn| build_setting_for_key(conn, key, None));
        }
        let def = lookup(key).ok_or_else(|| SettingsError::UnknownKey {
            key: key.into(),
        })?;
        self.with_conn(|conn| effective::build_setting(conn, def))
    }

    pub fn set(
        &self,
        values: &Map<String, Value>,
        strict: bool,
        expected_updated_at: Option<&Map<String, Value>>,
    ) -> Result<SetResult, SettingsError> {
        let sink = Arc::clone(&self.sink);
        let result = self.with_conn_mut(|conn| {
            set_values(
                conn,
                values,
                strict,
                expected_updated_at,
                sink.as_ref(),
            )
        })?;
        if !result.changed_keys.is_empty() {
            sink.emit(&result.changed_keys, "set");
        }
        Ok(result)
    }

    pub fn reset(&self) -> Result<ResetResult, SettingsError> {
        let sink = Arc::clone(&self.sink);
        let result = self.with_conn_mut(|conn| reset_settings(conn, sink.as_ref()))?;
        if !result.removed.is_empty() {
            sink.emit(&result.keys, "reset");
        }
        Ok(result)
    }

    pub fn connection(&self) -> Arc<Mutex<Connection>> {
        Arc::clone(&self.conn)
    }
}
