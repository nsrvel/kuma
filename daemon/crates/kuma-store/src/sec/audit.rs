use serde_json::{json, Map, Value};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};

const ROTATE_BYTES: u64 = 5 * 1024 * 1024;

#[derive(Clone)]
pub struct AuditLog {
    path: PathBuf,
}

impl AuditLog {
    pub fn open(data_dir: &Path) -> std::io::Result<Self> {
        let path = data_dir.join("audit.log");
        if !path.exists() {
            std::fs::File::create(&path)?;
        }
        set_mode(&path, 0o600)?;
        Ok(Self { path })
    }

    pub fn log_token_rotated(&self) {
        let _ = self.append(json!({
            "kind": "auth",
            "outcome": "ok",
            "reason": "token.rotated",
        }));
    }

    pub fn log_auth_reject(&self, reason: &str) {
        let _ = self.append(json!({
            "kind": "auth",
            "outcome": "rejected",
            "reason": reason,
        }));
    }

    pub fn log_rpc(
        &self,
        method: &str,
        outcome: &str,
        transport: &str,
        client_kind: &str,
        reveal: bool,
        params: &Value,
    ) {
        if !should_log_rpc(method, reveal) {
            return;
        }
        let _ = self.append(json!({
            "kind": if reveal { "reveal" } else { "rpc" },
            "method": method,
            "outcome": outcome,
            "transport": transport,
            "clientKind": client_kind,
            "reveal": reveal,
            "refs": refs_whitelist(params),
        }));
    }

    fn append(&self, mut entry: Value) -> std::io::Result<()> {
        self.rotate_if_needed()?;
        if let Some(obj) = entry.as_object_mut() {
            obj.insert(
                "ts".into(),
                json!(chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()),
            );
        }
        let line = serde_json::to_string(&entry).unwrap_or_else(|_| "{}".to_string());
        let mut file = OpenOptions::new().append(true).open(&self.path)?;
        writeln!(file, "{line}")?;
        Ok(())
    }

    fn rotate_if_needed(&self) -> std::io::Result<()> {
        let meta = std::fs::metadata(&self.path)?;
        if meta.len() < ROTATE_BYTES {
            return Ok(());
        }
        let dir = self.path.parent().unwrap_or(Path::new("."));
        for (from, to) in [
            ("audit.log.2", "audit.log.3"),
            ("audit.log.1", "audit.log.2"),
            ("audit.log", "audit.log.1"),
        ] {
            let a = dir.join(from);
            let b = dir.join(to);
            if a.exists() {
                let _ = std::fs::remove_file(&b);
                std::fs::rename(&a, &b)?;
            }
        }
        std::fs::File::create(&self.path)?;
        set_mode(&self.path, 0o600)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

pub fn should_log_rpc(method: &str, reveal: bool) -> bool {
    if reveal {
        return true;
    }
    is_mutating_method(method) || is_sensitive_read(method)
}

pub fn is_mutating_method(method: &str) -> bool {
    matches!(
        method,
        "daemon.shutdown"
            | "daemon.rotate_api_token"
            | "settings.set"
            | "settings.reset"
            | "workspace.create"
            | "workspace.update"
            | "workspace.delete"
            | "workspace.reorder"
            | "workspace.set_image"
            | "workspace.clear_image"
            | "group.create"
            | "group.update"
            | "group.delete"
            | "group.reorder"
            | "service.create"
            | "service.update"
            | "service.delete"
            | "service.duplicate"
            | "service.set_starred"
            | "service.set_disabled"
            | "service.set_groups"
            | "service.toggle_group"
            | "service.switch_provider"
            | "service.start"
            | "service.stop"
            | "service.restart"
            | "service.start_all"
            | "service.stop_all"
            | "provider.add"
            | "provider.update"
            | "provider.delete"
            | "provider.set_ports"
            | "kubeconfig.create"
            | "kubeconfig.update"
            | "kubeconfig.delete"
            | "logs.clear"
            | "data.import"
            | "data.factory_reset"
    )
}

fn is_sensitive_read(method: &str) -> bool {
    matches!(
        method,
        "data.export" | "data.export_service_json"
    )
}

fn refs_whitelist(params: &Value) -> Value {
    let Some(obj) = params.as_object() else {
        return json!({});
    };
    let keys = [
        "id",
        "serviceID",
        "workspaceID",
        "providerID",
        "groupID",
        "subscriptionId",
    ];
    let mut out = Map::new();
    for key in keys {
        if let Some(v) = obj.get(key) {
            out.insert(key.to_string(), v.clone());
        }
    }
    Value::Object(out)
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) -> std::io::Result<()> {
    Ok(())
}
