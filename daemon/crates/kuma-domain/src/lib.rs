//! Domain layer: no I/O, no async runtimes, no wire types.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum DomainError {
    #[error("invariant violated: {0}")]
    Invariant(&'static str),
}

/// Storage-layer errors ([`docs/specs/daemon/01-data-model.md`](../../docs/specs/daemon/01-data-model.md) §8).
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum StoreError {
    #[error("Failed to initialize SQLite database: {detail}")]
    DbOpenFailed { detail: String },
    #[error("Database was migrated by a newer version (unknown migration: {identifier}). Refusing to open.")]
    SchemaTooNew { identifier: String },
    #[error("Migration {identifier} failed: {detail}")]
    MigrationFailed { identifier: String, detail: String },
    #[error("Could not create database backup before migration: {detail}")]
    BackupFailed { detail: String },
    #[error("Failed to reset database: {detail}")]
    WipeFailed { detail: String },
    #[error("Stored row in {table} could not be decoded: {column}")]
    RowDecode { table: String, column: String },
    #[error("Invalid UUID: {value}")]
    InvalidUuid { value: String },
    #[error("Invalid timestamp: {value}")]
    InvalidTimestamp { value: String },
    #[error("Invalid value '{value}' for {field}")]
    InvalidEnum { field: String, value: String },
    #[error("Database constraint violated: {detail}")]
    ConstraintViolation { detail: String },
    #[error("Database is busy; another process holds a write lock.")]
    DbBusy,
}

/// Settings KV errors ([`docs/specs/daemon/03-settings-and-environment.md`](../../docs/specs/daemon/03-settings-and-environment.md) §8).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SettingsError {
    UnknownKey { key: String },
    InvalidType { key: String, expected: String },
    InvalidValue { key: String, message: String },
    ValueTooLarge { key: String },
    PathInvalid { key: String, message: String },
    ConflictStale { key: String },
}

impl SettingsError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::UnknownKey { .. } => "KUMA_SET_UNKNOWN_KEY",
            Self::InvalidType { .. } => "KUMA_SET_INVALID_TYPE",
            Self::InvalidValue { .. } => "KUMA_SET_INVALID_VALUE",
            Self::ValueTooLarge { .. } => "KUMA_SET_VALUE_TOO_LARGE",
            Self::PathInvalid { .. } => "KUMA_SET_PATH_INVALID",
            Self::ConflictStale { .. } => "KUMA_CONFLICT_STALE",
        }
    }

    pub fn message(&self) -> String {
        match self {
            Self::UnknownKey { key } => format!("Unknown setting key '{key}'"),
            Self::InvalidType { key, expected } => {
                format!("Setting '{key}' expects {expected}")
            }
            Self::InvalidValue { key, message } => {
                if message.is_empty() {
                    format!("Invalid value for '{key}'")
                } else {
                    format!("Invalid value for '{key}': {message}")
                }
            }
            Self::ValueTooLarge { key } => format!("Value for '{key}' exceeds 65536 bytes"),
            Self::PathInvalid { message, .. } => message.clone(),
            Self::ConflictStale { key } => format!("Stale concurrency token for '{key}'"),
        }
    }
}

impl std::fmt::Display for SettingsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for SettingsError {}

/// Workspace RPC errors ([04](docs/specs/daemon/04-workspaces-groups-services.md)).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceError {
    NotFound { id: String },
    NameEmpty,
    LastWorkspace { id: String },
    ImageInvalid,
    ImageConflict,
    ImageIo { detail: String },
    ReorderInvalid { message: String },
    ConflictStale,
}

impl WorkspaceError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::NotFound { .. } => "KUMA_WS_NOT_FOUND",
            Self::NameEmpty => "KUMA_WS_NAME_EMPTY",
            Self::LastWorkspace { .. } => "KUMA_WS_LAST_WORKSPACE",
            Self::ImageInvalid => "KUMA_WS_IMAGE_INVALID",
            Self::ImageConflict => "KUMA_WS_IMAGE_CONFLICT",
            Self::ImageIo { .. } => "KUMA_WS_IMAGE_IO",
            Self::ReorderInvalid { .. } => "KUMA_WS_REORDER_INVALID",
            Self::ConflictStale => "KUMA_CONFLICT_STALE",
        }
    }

    pub fn message(&self) -> String {
        match self {
            Self::NotFound { id } => format!("Workspace not found: {id}"),
            Self::NameEmpty => "Name cannot be empty".into(),
            Self::LastWorkspace { id } => {
                format!("Attempted to delete the sole remaining workspace {id}. Operation blocked.")
            }
            Self::ImageInvalid => "Failed to read image source".into(),
            Self::ImageConflict => "Specify either imageBase64 or clearImage, not both".into(),
            Self::ImageIo { detail } => detail.clone(),
            Self::ReorderInvalid { message } => message.clone(),
            Self::ConflictStale => "Stale concurrency token".into(),
        }
    }
}

impl std::fmt::Display for WorkspaceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for WorkspaceError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GroupError {
    NotFound { id: String },
    WorkspaceNotFound { id: String },
    ReorderInvalid { message: String },
    WorkspaceMismatch,
    ConflictStale,
}

impl GroupError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::NotFound { .. } => "KUMA_GRP_NOT_FOUND",
            Self::WorkspaceNotFound { .. } => "KUMA_WS_NOT_FOUND",
            Self::ReorderInvalid { .. } => "KUMA_GRP_REORDER_INVALID",
            Self::WorkspaceMismatch => "KUMA_GRP_WORKSPACE_MISMATCH",
            Self::ConflictStale => "KUMA_CONFLICT_STALE",
        }
    }

    pub fn message(&self) -> String {
        match self {
            Self::NotFound { id } => format!("Group not found: {id}"),
            Self::WorkspaceNotFound { id } => format!("Workspace not found: {id}"),
            Self::ReorderInvalid { message } => message.clone(),
            Self::WorkspaceMismatch => "Group does not belong to this workspace".into(),
            Self::ConflictStale => "Stale concurrency token".into(),
        }
    }
}

impl std::fmt::Display for GroupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for GroupError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServiceError {
    NotFound { id: String },
    WorkspaceNotFound { id: String },
    NameEmpty,
    InvalidPort { message: String },
    FieldReadonly { field: String },
    GroupNotFound { id: String },
    GroupWorkspaceMismatch,
    ProviderNotFound { id: String },
    LastProvider,
    ConflictStale,
}

impl ServiceError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::NotFound { .. } => "KUMA_SVC_NOT_FOUND",
            Self::WorkspaceNotFound { .. } => "KUMA_WS_NOT_FOUND",
            Self::NameEmpty => "KUMA_SVC_NAME_EMPTY",
            Self::InvalidPort { .. } => "KUMA_SVC_INVALID_PORT",
            Self::FieldReadonly { .. } => "KUMA_SVC_FIELD_READONLY",
            Self::GroupNotFound { .. } => "KUMA_GRP_NOT_FOUND",
            Self::GroupWorkspaceMismatch => "KUMA_GRP_WORKSPACE_MISMATCH",
            Self::ProviderNotFound { .. } => "KUMA_SVC_PROVIDER_NOT_FOUND",
            Self::LastProvider => "KUMA_SVC_LAST_PROVIDER",
            Self::ConflictStale => "KUMA_CONFLICT_STALE",
        }
    }

    pub fn message(&self) -> String {
        match self {
            Self::NotFound { id } => format!("Service not found: {id}"),
            Self::WorkspaceNotFound { id } => format!("Workspace not found: {id}"),
            Self::NameEmpty => "Service name cannot be empty".into(),
            Self::InvalidPort { message } => message.clone(),
            Self::FieldReadonly { field } => {
                format!("Field '{field}' is read-only on service.update")
            }
            Self::GroupNotFound { id } => format!("Group not found: {id}"),
            Self::GroupWorkspaceMismatch => "Group does not belong to this workspace".into(),
            Self::ProviderNotFound { id } => format!("Provider not found: {id}"),
            Self::LastProvider => "Cannot delete the last provider".into(),
            Self::ConflictStale => "Stale concurrency token".into(),
        }
    }
}

impl std::fmt::Display for ServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for ServiceError {}

/// Kubeconfig CRUD ([07](docs/specs/daemon/07-kubernetes.md)).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KubeConfigError {
    NotFound { id: String },
    DefaultImmutable,
    NameEmpty,
    ContentEmpty,
    Io { detail: String },
    KubectlNotFound,
    KubectlFailed { detail: String },
    InvalidEnum { field: String, value: String },
}

impl KubeConfigError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::NotFound { .. } => "KUMA_K8S_NOT_FOUND",
            Self::DefaultImmutable => "KUMA_K8S_DEFAULT_IMMUTABLE",
            Self::NameEmpty => "KUMA_K8S_NAME_EMPTY",
            Self::ContentEmpty => "KUMA_K8S_CONTENT_EMPTY",
            Self::Io { .. } => "KUMA_K8S_IO",
            Self::KubectlNotFound => "KUMA_K8S_KUBECTL_NOT_FOUND",
            Self::KubectlFailed { .. } => "KUMA_K8S_KUBECTL_FAILED",
            Self::InvalidEnum { .. } => "KUMA_DAT_INVALID_ENUM",
        }
    }

    pub fn message(&self) -> String {
        match self {
            Self::NotFound { id } => format!("Kubeconfig not found: {id}"),
            Self::DefaultImmutable => "The default kubeconfig cannot be modified".into(),
            Self::NameEmpty => "Name cannot be empty".into(),
            Self::ContentEmpty => "Kubeconfig content cannot be empty".into(),
            Self::Io { detail } => detail.clone(),
            Self::KubectlNotFound => {
                "Required binary 'kubectl' could not be located on this Mac.".into()
            }
            Self::KubectlFailed { detail } => detail.clone(),
            Self::InvalidEnum { field, value } => {
                format!("Invalid value '{value}' for {field}")
            }
        }
    }
}

impl std::fmt::Display for KubeConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for KubeConfigError {}

impl StoreError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::DbOpenFailed { .. } => "KUMA_DAT_DB_OPEN_FAILED",
            Self::SchemaTooNew { .. } => "KUMA_DAT_SCHEMA_TOO_NEW",
            Self::MigrationFailed { .. } => "KUMA_DAT_MIGRATION_FAILED",
            Self::BackupFailed { .. } => "KUMA_DAT_BACKUP_FAILED",
            Self::WipeFailed { .. } => "KUMA_DAT_WIPE_FAILED",
            Self::RowDecode { .. } => "KUMA_DAT_ROW_DECODE",
            Self::InvalidUuid { .. } => "KUMA_DAT_INVALID_UUID",
            Self::InvalidTimestamp { .. } => "KUMA_DAT_INVALID_TIMESTAMP",
            Self::InvalidEnum { .. } => "KUMA_DAT_INVALID_ENUM",
            Self::ConstraintViolation { .. } => "KUMA_DAT_CONSTRAINT_VIOLATION",
            Self::DbBusy => "KUMA_DAT_DB_BUSY",
        }
    }
}
