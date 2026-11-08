mod backup;
mod daemon_state;
mod dataport;
mod env;
mod events;
mod group;
pub mod kubeconfig;
mod kuma_db;
mod legacy_import;
mod logs;
mod migrate;
mod provider;
mod runtime_process;
mod schema;
mod sec;
mod seed;
mod service;
mod settings;
mod validation;
mod workspace;

use daemon_state::DaemonStateDb;
pub use kuma_domain::{SettingsError, StoreError};
use migrate::{
    apply_all_pending, ensure_default_workspace_if_empty, ensure_grdb_migrations_table,
    pending_migrations, refuse_unknown_identifiers,
};
use rusqlite::Connection;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

pub use daemon_state::list_user_tables;
pub use kuma_db::{
    foreign_keys_enabled, is_sqlite_file, journal_mode, open_kuma_connection, table_count,
};
pub use legacy_import::run_legacy_import;
pub use migrate::{apply_through, read_applied_identifiers};
pub use schema::{EXPECTED_SQLITE_MASTER, KNOWN_MIGRATION_IDENTIFIERS};
pub use seed::{new_uppercase_uuid, now_grdb_datetime};
pub use env::EnvService;
pub use events::EventBus;
pub use group::GroupStore;
pub use provider::ProviderStore;
pub use service::ServiceStore;
pub use settings::{ChangeEvent, RecordingChangeSink, SettingsStore, REGISTRY, RESET_KEYS};
pub use workspace::WorkspaceStore;
pub use runtime_process::RuntimeProcessStore;
pub use dataport::DataPort;
pub use kubeconfig::KubeConfigStore;
pub use logs::LogBuffer;
pub use sec::{api_token_path, ensure_api_token, rotate_api_token, AuditLog, Vault};
pub use validation::{display_name, extract_compose_image};

pub type SqliteMasterRow = (String, String, String, Option<String>);

/// Opened storage ([01 §3.2](docs/specs/daemon/01-data-model.md)).
pub struct StoreHandle {
    kuma_path: PathBuf,
    data_dir: PathBuf,
    kuma: Arc<Mutex<Connection>>,
    daemon_state: DaemonStateDb,
    settings: SettingsStore,
    events: Arc<EventBus>,
    env: EnvService,
    workspace: WorkspaceStore,
    group: GroupStore,
    service: ServiceStore,
    provider: ProviderStore,
    kubeconfig: KubeConfigStore,
    logs: LogBuffer,
    dataport: DataPort,
    vault: Vault,
    audit: AuditLog,
    runtime_process: RuntimeProcessStore,
    schema_migrations: Vec<String>,
    instance_id: String,
}

impl StoreHandle {
    /// ponytail: opens DB before Unix listener bind (S6-before-accept); full S1–S13 reorder later.
    pub fn open(data_dir: &Path) -> Result<Self, StoreError> {
        std::fs::create_dir_all(data_dir).map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        let kuma_path = data_dir.join("kuma.sqlite");
        let conn = kuma_db::open_kuma_connection(&kuma_path)?;

        ensure_grdb_migrations_table(&conn)?;
        let applied = migrate::read_applied_identifiers(&conn)?;
        refuse_unknown_identifiers(&applied)?;

        let pending = pending_migrations(&applied);
        if !pending.is_empty() && !applied.is_empty() {
            backup::backup_before_migrate(&kuma_path, data_dir)?;
        }
        if !pending.is_empty() {
            backup::maybe_pre_daemon_backup(&kuma_path, data_dir)?;
        }

        apply_all_pending(&conn)?;
        ensure_default_workspace_if_empty(&conn)?;

        let schema_migrations = migrate::read_applied_identifiers(&conn)?;

        let daemon_path = data_dir.join("daemon-state.sqlite");
        let daemon_state = DaemonStateDb::open(&daemon_path)?;
        let daemon_conn = daemon_state.connection();
        {
            let guard = daemon_conn
                .lock()
                .map_err(|_| StoreError::DbOpenFailed {
                    detail: "daemon-state lock poisoned".into(),
                })?;
            run_legacy_import(&guard)?;
        }
        let instance_id = daemon_state.instance_id().to_string();
        let kuma = Arc::new(Mutex::new(conn));
        let daemon_conn = daemon_state.connection();
        let events = Arc::new(EventBus::new(daemon_conn.clone())?);
        let settings = SettingsStore::new(daemon_conn, events.settings_sink());
        let env = EnvService::new(settings.clone());
        let workspace = WorkspaceStore::new(Arc::clone(&kuma), data_dir.to_path_buf());
        let group = GroupStore::new(Arc::clone(&kuma));
        let service = ServiceStore::new(Arc::clone(&kuma));
        let provider = ProviderStore::new(Arc::clone(&kuma));
        let vault = Vault::open(data_dir)?;
        let kubeconfig = KubeConfigStore::new(
            Arc::clone(&kuma),
            data_dir.to_path_buf(),
            settings.clone(),
            vault.clone(),
        );
        let dataport = DataPort::new(Arc::clone(&kuma), data_dir.to_path_buf());
        let _ = ensure_api_token(data_dir);
        let logs = LogBuffer::new();
        let audit = AuditLog::open(data_dir).map_err(|e| StoreError::DbOpenFailed {
            detail: format!("audit.log: {e}"),
        })?;
        let runtime_process = RuntimeProcessStore::new(&daemon_state);

        Ok(Self {
            kuma_path,
            data_dir: data_dir.to_path_buf(),
            kuma,
            daemon_state,
            settings,
            events,
            env,
            workspace,
            group,
            service,
            provider,
            kubeconfig,
            logs,
            dataport,
            vault,
            audit,
            runtime_process,
            schema_migrations,
            instance_id,
        })
    }

    pub fn kuma_db_path(&self) -> &Path {
        &self.kuma_path
    }

    pub fn schema_migrations(&self) -> &[String] {
        &self.schema_migrations
    }

    pub fn instance_id(&self) -> &str {
        &self.instance_id
    }

    pub fn settings(&self) -> &SettingsStore {
        &self.settings
    }

    pub fn events(&self) -> &Arc<EventBus> {
        &self.events
    }

    pub fn env(&self) -> &EnvService {
        &self.env
    }

    pub fn workspace(&self) -> &WorkspaceStore {
        &self.workspace
    }

    pub fn group(&self) -> &GroupStore {
        &self.group
    }

    pub fn service(&self) -> &ServiceStore {
        &self.service
    }

    pub fn provider(&self) -> &ProviderStore {
        &self.provider
    }

    pub fn kubeconfig(&self) -> &KubeConfigStore {
        &self.kubeconfig
    }

    pub fn logs(&self) -> &LogBuffer {
        &self.logs
    }

    pub fn dataport(&self) -> &DataPort {
        &self.dataport
    }

    pub fn vault(&self) -> &Vault {
        &self.vault
    }

    pub fn audit(&self) -> &AuditLog {
        &self.audit
    }

    pub fn runtime_process(&self) -> &RuntimeProcessStore {
        &self.runtime_process
    }

    pub fn data_dir(&self) -> &Path {
        &self.data_dir
    }

    pub fn workspace_count(&self) -> Result<u64, StoreError> {
        let guard = self.kuma.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "kuma lock poisoned".into(),
        })?;
        kuma_db::table_count(&guard, "workspace")
    }

    pub fn service_count(&self) -> Result<u64, StoreError> {
        let guard = self.kuma.lock().map_err(|_| StoreError::DbOpenFailed {
            detail: "kuma lock poisoned".into(),
        })?;
        kuma_db::table_count(&guard, "service")
    }

    pub fn kuma_connection(&self) -> Arc<Mutex<Connection>> {
        Arc::clone(&self.kuma)
    }

    pub fn daemon_state_connection(&self) -> Arc<Mutex<Connection>> {
        self.daemon_state.connection()
    }
}

/// Test helper: snapshot user `sqlite_master` rows in rowid order.
pub fn fetch_sqlite_master(conn: &Connection) -> Result<Vec<SqliteMasterRow>, StoreError> {
    let mut stmt = conn
        .prepare(
            "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY rowid",
        )
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get(0)?,
                r.get(1)?,
                r.get(2)?,
                r.get::<_, Option<String>>(3)?,
            ))
        })
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(rows)
}

pub fn assert_expected_schema(conn: &Connection) -> Result<(), StoreError> {
    let live = fetch_sqlite_master(conn)?;
    let expected: Vec<_> = EXPECTED_SQLITE_MASTER
        .iter()
        .map(|(t, n, tbl, sql)| {
            (
                (*t).to_string(),
                (*n).to_string(),
                (*tbl).to_string(),
                sql.map(|s| s.to_string()),
            )
        })
        .collect();
    if live != expected {
        return Err(StoreError::DbOpenFailed {
            detail: format!(
                "sqlite_master mismatch: expected {} objects, got {}",
                expected.len(),
                live.len()
            ),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::migrate::apply_through;

    #[test]
    fn apply_through_v2_leaves_pending_highers() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("kuma.sqlite");
        let conn = kuma_db::open_kuma_connection(&path).unwrap();
        apply_through(&conn, 1).unwrap();
        let applied = migrate::read_applied_identifiers(&conn).unwrap();
        assert_eq!(applied.len(), 2);
        assert_eq!(applied[1], "v2_service_groups");
    }
}
