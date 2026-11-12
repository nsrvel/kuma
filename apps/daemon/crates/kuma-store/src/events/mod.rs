use crate::settings::SettingsChangeSink;
use kuma_domain::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const EVENT_SEQ_KEY: &str = "eventSeq";
const REPLAY_CAPACITY: usize = 10_000;

#[derive(Clone)]
pub struct StoredEvent {
    pub seq: u64,
    pub name: String,
    pub payload: Value,
}

pub struct EventBus {
    conn: Arc<Mutex<Connection>>,
    buffer: Mutex<Vec<StoredEvent>>,
    subs: Mutex<HashMap<String, Vec<String>>>,
    live: Mutex<Vec<Sender<String>>>,
}

impl EventBus {
    pub fn new(conn: Arc<Mutex<Connection>>) -> Result<Self, StoreError> {
        let guard = conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "lock poisoned".into(),
        })?;
        ensure_event_seq(&guard)?;
        drop(guard);
        Ok(Self {
            conn,
            buffer: Mutex::new(Vec::new()),
            subs: Mutex::new(HashMap::new()),
            live: Mutex::new(Vec::new()),
        })
    }

    pub fn live_subscribe(&self) -> Receiver<String> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.live.lock().unwrap().push(tx);
        rx
    }

    pub fn publish(&self, name: &str, payload: Value) -> Result<u64, StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "lock poisoned".into(),
        })?;
        let seq = next_seq(&conn)?;
        conn.execute(
            "INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![EVENT_SEQ_KEY, seq.to_string()],
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        drop(conn);
        let event = StoredEvent {
            seq,
            name: name.into(),
            payload,
        };
        let wire = json!({
            "seq": seq,
            "name": name,
            "payload": &event.payload,
        });
        let mut buf = self.buffer.lock().unwrap();
        buf.push(event);
        if buf.len() > REPLAY_CAPACITY {
            let drop_n = buf.len() - REPLAY_CAPACITY;
            buf.drain(0..drop_n);
        }
        if let Ok(line) = serde_json::to_string(&wire) {
            let mut live = self.live.lock().unwrap();
            live.retain(|tx| tx.send(line.clone()).is_ok());
        }
        Ok(seq)
    }

    pub fn replay(&self, since_seq: u64, topics: Option<&[String]>) -> (Vec<Value>, u64, bool) {
        let buf = self.buffer.lock().unwrap();
        let oldest = buf.first().map(|e| e.seq).unwrap_or(0);
        let replay_from = if since_seq < oldest && !buf.is_empty() {
            oldest
        } else {
            since_seq
        };
        let truncated = since_seq < oldest && !buf.is_empty();
        let events: Vec<Value> = buf
            .iter()
            .filter(|e| e.seq > since_seq)
            .filter(|e| {
                topics
                    .map(|t| t.is_empty() || t.contains(&e.name))
                    .unwrap_or(true)
            })
            .map(|e| {
                json!({
                    "seq": e.seq,
                    "name": e.name,
                    "payload": e.payload,
                })
            })
            .collect();
        (events, replay_from, truncated)
    }

    pub fn subscribe(&self, topics: Vec<String>) -> String {
        let id = Uuid::new_v4().to_string();
        self.subs.lock().unwrap().insert(id.clone(), topics);
        id
    }

    pub fn unsubscribe(&self, subscription_id: &str) -> bool {
        self.subs.lock().unwrap().remove(subscription_id).is_some()
    }

    pub fn settings_sink(self: &Arc<Self>) -> Arc<dyn SettingsChangeSink> {
        Arc::new(BusSettingsSink {
            bus: Arc::clone(self),
        })
    }
}

struct BusSettingsSink {
    bus: Arc<EventBus>,
}

impl SettingsChangeSink for BusSettingsSink {
    fn emit(&self, keys: &[String], reason: &str) {
        let _ = self.bus.publish(
            "settings.changed",
            json!({ "reason": reason, "keys": keys }),
        );
    }
}

fn ensure_event_seq(conn: &Connection) -> Result<(), StoreError> {
    let _: Option<String> = conn
        .query_row(
            "SELECT value FROM meta WHERE key = ?1",
            [EVENT_SEQ_KEY],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(())
}

fn next_seq(conn: &Connection) -> Result<u64, StoreError> {
    let current: Option<String> = conn
        .query_row(
            "SELECT value FROM meta WHERE key = ?1",
            [EVENT_SEQ_KEY],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(current
        .and_then(|s| s.parse().ok())
        .unwrap_or(0u64)
        .saturating_add(1))
}

use rusqlite::OptionalExtension;
