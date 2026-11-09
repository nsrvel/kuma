use kuma_protocol::paths;
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Mutex;

const MAX_LINES: usize = 500;

static NEXT_FOLLOW_SUB: AtomicU64 = AtomicU64::new(1);

pub struct LogBuffer {
    inner: Mutex<HashMap<String, VecDeque<String>>>,
    subscribers: Mutex<HashMap<String, Vec<Sender<String>>>>,
    follow_registry: Mutex<HashMap<String, String>>,
    spool_dir: PathBuf,
}

impl LogBuffer {
    pub fn new() -> Self {
        let spool_dir = paths::runtime_dir().join("logs");
        let _ = std::fs::create_dir_all(&spool_dir);
        Self {
            inner: Mutex::new(HashMap::new()),
            subscribers: Mutex::new(HashMap::new()),
            follow_registry: Mutex::new(HashMap::new()),
            spool_dir,
        }
    }

    pub fn append(&self, service_id: &str, line: impl Into<String>) {
        let line = line.into();
        {
            let mut map = self.inner.lock().unwrap_or_else(|e| e.into_inner());
            let buf = map.entry(service_id.to_string()).or_default();
            if buf.len() >= MAX_LINES {
                buf.pop_front();
            }
            buf.push_back(line.clone());
        }
        let path = self.spool_path(service_id);
        if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&path) {
            let _ = writeln!(f, "{line}");
        }
        self.notify(service_id, &line);
    }

    pub fn subscribe(&self, service_id: &str) -> Receiver<String> {
        let (tx, rx) = mpsc::channel();
        self.subscribers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(service_id.to_string())
            .or_default()
            .push(tx);
        rx
    }

    fn notify(&self, service_id: &str, line: &str) {
        let mut subs = self.subscribers.lock().unwrap_or_else(|e| e.into_inner());
        let Some(chans) = subs.get_mut(service_id) else {
            return;
        };
        chans.retain(|tx| tx.send(line.to_string()).is_ok());
    }

    pub fn tail(&self, service_id: &str, limit: usize) -> Value {
        let file_lines = self.read_spool_tail(service_id, limit);
        if !file_lines.is_empty() {
            return json!({ "lines": file_lines });
        }
        let map = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        let empty = VecDeque::new();
        let buf = map.get(service_id).unwrap_or(&empty);
        let start = buf.len().saturating_sub(limit.max(1));
        let lines: Vec<&str> = buf.iter().skip(start).map(String::as_str).collect();
        json!({ "lines": lines })
    }

    pub fn clear(&self, service_id: &str) -> Value {
        let mut map = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        map.remove(service_id);
        let path = self.spool_path(service_id);
        if path.exists() {
            let _ = std::fs::remove_file(path);
        }
        json!({ "cleared": true })
    }

    pub fn follow_snapshot(&self, service_id: &str) -> Value {
        self.start_follow(service_id)
    }

    pub fn start_follow(&self, service_id: &str) -> Value {
        let sub_id = NEXT_FOLLOW_SUB.fetch_add(1, Ordering::Relaxed).to_string();
        self.follow_registry
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(sub_id.clone(), service_id.to_string());
        let lines = self.read_spool_tail(service_id, 50);
        json!({
            "following": true,
            "serviceID": service_id,
            "subscriptionId": sub_id,
            "lines": lines,
            "stream": true,
        })
    }

    pub fn follow_service_for_sub(&self, subscription_id: &str) -> Option<String> {
        self.follow_registry
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(subscription_id)
            .cloned()
    }

    pub fn end_follow(&self, subscription_id: &str) -> bool {
        self.follow_registry
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(subscription_id)
            .is_some()
    }

    fn spool_path(&self, service_id: &str) -> PathBuf {
        self.spool_dir.join(format!("{service_id}.ndjson"))
    }

    fn read_spool_tail(&self, service_id: &str, limit: usize) -> Vec<String> {
        let path = self.spool_path(service_id);
        let Ok(f) = File::open(path) else {
            return Vec::new();
        };
        let reader = BufReader::new(f);
        let all: Vec<String> = reader.lines().map_while(Result::ok).collect();
        let start = all.len().saturating_sub(limit.max(1));
        all.into_iter().skip(start).collect()
    }
}

impl Default for LogBuffer {
    fn default() -> Self {
        Self::new()
    }
}
