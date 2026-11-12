use crate::supervisor::StateNotify;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::process::Child;
use std::sync::{Arc, Mutex};

pub type LogSink = dyn Fn(&str, &str) + Send + Sync;

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct RunRecord {
    pub category: String,
    pub started_at: String,
}

#[derive(Debug, Clone)]
pub struct RuntimeSnapshot {
    pub status: String,
    pub is_loading: bool,
    pub status_title: String,
}

impl Default for RuntimeSnapshot {
    fn default() -> Self {
        Self {
            status: "stopped".into(),
            is_loading: false,
            status_title: "Stopped".into(),
        }
    }
}

#[derive(Debug, Clone, thiserror::Error)]
pub enum ExecError {
    #[error("service already running")]
    AlreadyRunning,
    #[error("service not running")]
    NotRunning,
    #[error("{0}")]
    Message(String),
}

pub struct ExecEngine {
    states: Mutex<HashMap<String, RuntimeSnapshot>>,
    pub(crate) children: Mutex<HashMap<String, Child>>,
    categories: Mutex<HashMap<String, String>>,
    logs: Mutex<HashMap<String, Vec<String>>>,
    adopted: Mutex<u64>,
    released: Mutex<u64>,
    run_records: Mutex<HashMap<String, RunRecord>>,
    log_sink: Mutex<Option<Arc<LogSink>>>,
    reconnect_budget: Mutex<HashMap<String, u8>>,
    state_notifier: Mutex<Option<StateNotify>>,
    adoption_details: Mutex<Vec<Value>>,
}

impl ExecEngine {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            states: Mutex::new(HashMap::new()),
            children: Mutex::new(HashMap::new()),
            categories: Mutex::new(HashMap::new()),
            logs: Mutex::new(HashMap::new()),
            adopted: Mutex::new(0),
            released: Mutex::new(0),
            log_sink: Mutex::new(None),
            run_records: Mutex::new(HashMap::new()),
            reconnect_budget: Mutex::new(HashMap::new()),
            state_notifier: Mutex::new(None),
            adoption_details: Mutex::new(Vec::new()),
        })
    }

    pub fn set_state_notifier(&self, notifier: StateNotify) {
        *self.state_notifier.lock().unwrap() = Some(notifier);
    }

    fn emit_state(&self, service_id: &str) {
        let status = self.snapshot(service_id).status;
        if let Some(n) = self.state_notifier.lock().unwrap().as_ref() {
            n(service_id, &status);
        }
    }

    pub fn adopt_persisted_processes(&self, rows: &[(String, u32)]) {
        for (sid, pid) in rows {
            self.set_running(sid);
            self.adoption_details.lock().unwrap().push(json!({
                "serviceID": sid,
                "pid": pid,
                "adopted": true,
            }));
        }
        if !rows.is_empty() {
            *self.adopted.lock().unwrap() = rows.len() as u64;
        }
    }

    pub fn adoption_report_json(&self) -> Value {
        let details = self.adoption_details.lock().unwrap().clone();
        json!({
            "adopted": self.adopted_count(),
            "released": self.released_count(),
            "services": details,
        })
    }

    pub fn reset_reconnect_budget(&self, service_id: &str) {
        self.reconnect_budget
            .lock()
            .unwrap()
            .insert(service_id.to_string(), 3);
    }

    pub fn consume_reconnect_slot(&self, service_id: &str) -> bool {
        let mut map = self.reconnect_budget.lock().unwrap();
        let budget = map.entry(service_id.to_string()).or_insert(3);
        if *budget == 0 {
            return false;
        }
        *budget -= 1;
        true
    }

    pub fn record_run(&self, service_id: &str, category: &str) {
        let ts = chrono::Utc::now()
            .format("%Y-%m-%dT%H:%M:%S%.3fZ")
            .to_string();
        self.run_records.lock().unwrap().insert(
            service_id.to_string(),
            RunRecord {
                category: category.to_string(),
                started_at: ts,
            },
        );
        *self.adopted.lock().unwrap() += 1;
    }

    pub fn run_records_json(&self) -> Value {
        let map = self.run_records.lock().unwrap();
        let n = map.len();
        json!({ "count": n, "records": n })
    }

    pub fn set_log_sink(&self, sink: Arc<LogSink>) {
        *self.log_sink.lock().unwrap() = Some(sink);
    }

    pub fn append_log(&self, service_id: &str, line: String) {
        {
            let mut logs = self.logs.lock().unwrap();
            let buf = logs.entry(service_id.to_string()).or_default();
            buf.push(line.clone());
            if buf.len() > 500 {
                buf.remove(0);
            }
        }
        if let Some(sink) = self.log_sink.lock().unwrap().as_ref() {
            sink(service_id, &line);
        }
    }

    pub fn adopted_count(&self) -> u64 {
        *self.adopted.lock().unwrap()
    }

    pub fn released_count(&self) -> u64 {
        *self.released.lock().unwrap()
    }

    pub fn record_release(&self) {
        *self.released.lock().unwrap() += 1;
    }

    pub fn run_category(&self, service_id: &str) -> Option<String> {
        self.categories.lock().unwrap().get(service_id).cloned()
    }

    pub fn set_running_category(&self, service_id: &str, category: &str) {
        self.set_running(service_id);
        self.record_run(service_id, category);
        self.categories
            .lock()
            .unwrap()
            .insert(service_id.to_string(), category.to_string());
    }

    pub fn set_starting(&self, service_id: &str) {
        self.states.lock().unwrap().insert(
            service_id.to_string(),
            RuntimeSnapshot {
                status: "starting".into(),
                is_loading: true,
                status_title: "Starting".into(),
            },
        );
        self.emit_state(service_id);
    }

    pub fn set_stopping(&self, service_id: &str) {
        self.states.lock().unwrap().insert(
            service_id.to_string(),
            RuntimeSnapshot {
                status: "stopping".into(),
                is_loading: true,
                status_title: "Stopping".into(),
            },
        );
        self.emit_state(service_id);
    }

    pub fn set_reconnecting(&self, service_id: &str) {
        self.states.lock().unwrap().insert(
            service_id.to_string(),
            RuntimeSnapshot {
                status: "reconnecting".into(),
                is_loading: true,
                status_title: "Reconnecting".into(),
            },
        );
        self.emit_state(service_id);
    }

    pub fn scan_spool_adoption(&self) {
        // ponytail: ndjson spool count only; full stack adoption in adopt_persisted_processes
        let dir = kuma_protocol::paths::runtime_dir().join("logs");
        let Ok(read) = std::fs::read_dir(dir) else {
            return;
        };
        let n = read
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "ndjson"))
            .count() as u64;
        if n > 0 && self.adopted_count() == 0 {
            *self.adopted.lock().unwrap() = n;
        }
    }

    pub fn snapshot(&self, service_id: &str) -> RuntimeSnapshot {
        self.states
            .lock()
            .unwrap()
            .get(service_id)
            .cloned()
            .unwrap_or_default()
    }

    pub fn status_json(&self, service_id: &str) -> Value {
        let s = self.snapshot(service_id);
        json!({
            "serviceID": service_id,
            "status": s.status,
            "isLoading": s.is_loading,
            "statusTitle": s.status_title,
        })
    }

    pub fn statuses_json(&self, ids: &[String]) -> Value {
        let items: Vec<_> = ids.iter().map(|id| self.status_json(id)).collect();
        json!({ "statuses": items })
    }

    pub fn running_service_ids(&self) -> Vec<String> {
        self.states
            .lock()
            .unwrap()
            .iter()
            .filter(|(_, s)| matches!(s.status.as_str(), "running" | "starting" | "reconnecting"))
            .map(|(id, _)| id.clone())
            .collect()
    }

    pub fn set_running(&self, service_id: &str) {
        self.states.lock().unwrap().insert(
            service_id.to_string(),
            RuntimeSnapshot {
                status: "running".into(),
                is_loading: false,
                status_title: "Running".into(),
            },
        );
        self.emit_state(service_id);
    }

    pub fn set_stopped(&self, service_id: &str) {
        self.states
            .lock()
            .unwrap()
            .insert(service_id.to_string(), RuntimeSnapshot::default());
        self.categories.lock().unwrap().remove(service_id);
        self.emit_state(service_id);
    }

    pub fn stop_all(&self) -> usize {
        let ids = self.running_service_ids();
        for sid in &ids {
            if let Some(mut child) = self.take_child(sid) {
                let _ = child.kill();
                let _ = child.wait();
            }
            self.set_stopped(sid);
        }
        ids.len()
    }

    pub fn register_child(&self, service_id: &str, child: Child) {
        self.children
            .lock()
            .unwrap()
            .insert(service_id.to_string(), child);
    }

    pub fn take_child(&self, service_id: &str) -> Option<Child> {
        self.children.lock().unwrap().remove(service_id)
    }

    pub fn child_pid(&self, service_id: &str) -> Option<u32> {
        self.children
            .lock()
            .unwrap()
            .get(service_id)
            .map(|c| c.id())
    }
}
