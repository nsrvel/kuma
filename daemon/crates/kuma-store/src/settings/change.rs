use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Default)]
pub struct ChangeEvent {
    pub keys: Vec<String>,
    pub reason: String,
}

pub trait SettingsChangeSink: Send + Sync {
    fn emit(&self, keys: &[String], reason: &str);
}

#[allow(dead_code)]
pub struct NoopChangeSink;

impl SettingsChangeSink for NoopChangeSink {
    fn emit(&self, _keys: &[String], _reason: &str) {}
}

pub struct RecordingChangeSink {
    inner: Arc<Mutex<Vec<ChangeEvent>>>,
}

impl RecordingChangeSink {
    pub fn new() -> (Self, Arc<Mutex<Vec<ChangeEvent>>>) {
        let inner = Arc::new(Mutex::new(Vec::new()));
        (
            Self {
                inner: Arc::clone(&inner),
            },
            inner,
        )
    }
}

impl SettingsChangeSink for RecordingChangeSink {
    fn emit(&self, keys: &[String], reason: &str) {
        self.inner.lock().unwrap().push(ChangeEvent {
            keys: keys.to_vec(),
            reason: reason.into(),
        });
    }
}
