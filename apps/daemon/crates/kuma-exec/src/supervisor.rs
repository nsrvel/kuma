use std::collections::BTreeMap;

pub type StateNotify = Arc<dyn Fn(&str, &str) + Send + Sync>;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

/// Trailing-edge debounce (~100ms) for `service.state_changed` publications (DEV-74).
pub struct StateSupervisor {
    tx: Sender<(String, String)>,
}

impl StateSupervisor {
    pub fn new(publish: StateNotify) -> Self {
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || run_debounce_loop(rx, publish));
        Self { tx }
    }

    pub fn notify(&self, service_id: &str, status: &str) {
        let _ = self.tx.send((service_id.to_string(), status.to_string()));
    }
}

fn run_debounce_loop(rx: Receiver<(String, String)>, publish: StateNotify) {
    let mut pending: BTreeMap<String, String> = BTreeMap::new();
    loop {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok((sid, status)) => {
                pending.insert(sid, status);
            }
            Err(RecvTimeoutError::Timeout) => {
                flush(&mut pending, &publish);
            }
            Err(RecvTimeoutError::Disconnected) => {
                flush(&mut pending, &publish);
                break;
            }
        }
    }
}

fn flush(pending: &mut BTreeMap<String, String>, publish: &StateNotify) {
    if pending.is_empty() {
        return;
    }
    for (sid, status) in pending.iter() {
        publish(sid, status);
    }
    pending.clear();
}
