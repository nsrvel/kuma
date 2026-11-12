//! Daemon lifecycle snapshot (no I/O).

use std::time::Instant;

/// Process-local daemon metadata for `daemon.status`.
#[derive(Debug, Clone)]
pub struct LifecycleState {
    /// Daemon binary / package version (spec 14 §4.1 `version`).
    pub daemon_version: String,
    pub started_at: Instant,
    /// Uppercase UUID string (ADD-115 / meta.instanceId).
    pub instance_id: String,
}

impl LifecycleState {
    pub fn new(daemon_version: impl Into<String>, instance_id: String) -> Self {
        Self {
            daemon_version: daemon_version.into(),
            started_at: Instant::now(),
            instance_id,
        }
    }

    pub fn uptime_secs(&self) -> u64 {
        self.started_at.elapsed().as_secs()
    }
}

/// Counts loaded at daemon boot from `kuma-store`.
#[derive(Debug, Clone, Default)]
pub struct DataCounts {
    pub workspace_count: u64,
    pub service_count: u64,
    pub schema_migrations: Vec<String>,
}

impl DataCounts {
    pub fn empty() -> Self {
        Self::default()
    }
}
