use crate::sec::wire::{decrypt_kube_config_content, encrypt_kube_config_content};
use crate::seed::{new_uppercase_uuid, now_grdb_datetime};
use crate::settings::SettingsStore;
use crate::Vault;
use kuma_domain::KubeConfigError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

pub const DEFAULT_ID: &str = "00000000-0000-0000-0000-000000000001";

#[derive(Clone)]
pub struct KubeConfigStore {
    conn: Arc<Mutex<Connection>>,
    data_dir: PathBuf,
    settings: SettingsStore,
    vault: Vault,
}

impl KubeConfigStore {
    pub fn new(
        conn: Arc<Mutex<Connection>>,
        data_dir: PathBuf,
        settings: SettingsStore,
        vault: Vault,
    ) -> Self {
        Self {
            conn,
            data_dir,
            settings,
            vault,
        }
    }

    pub fn list(&self) -> Result<Value, KubeConfigError> {
        let conn = self.conn.lock().map_err(|_| io_err("lock poisoned"))?;
        let default = default_entry(&self.settings)?;
        let mut stmt = conn
            .prepare(
                "SELECT id, name, configContent, createdAt, updatedAt, sourceFilePath FROM kube_config WHERE id != ?1 ORDER BY name ASC",
            )
            .map_err(|e| io_err(&e.to_string()))?;
        let rows = stmt
            .query_map([DEFAULT_ID], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, Option<String>>(5)?,
                ))
            })
            .map_err(|e| io_err(&e.to_string()))?;
        let mut items = vec![default];
        for row in rows {
            let (id, name, _, created, updated, source) =
                row.map_err(|e| io_err(&e.to_string()))?;
            items.push(wire_summary(&id, &name, false, &created, &updated, source));
        }
        Ok(json!({ "kubeconfigs": items }))
    }

    pub fn get(&self, id: &str, reveal_content: bool) -> Result<Value, KubeConfigError> {
        let id = normalize_id(id)?;
        if id == DEFAULT_ID {
            let mut entry = default_entry(&self.settings)?;
            if reveal_content {
                entry["configContent"] = json!(default_plain_yaml(&self.settings)?);
            } else {
                entry["hasConfigContent"] = json!(true);
            }
            return Ok(json!({ "kubeconfig": entry }));
        }
        let conn = self.conn.lock().map_err(|_| io_err("lock poisoned"))?;
        let row: Option<(String, String, String, String, String, Option<String>)> = conn
            .query_row(
                "SELECT id, name, configContent, createdAt, updatedAt, sourceFilePath FROM kube_config WHERE id = ?1",
                [&id],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                        row.get(5)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| io_err(&e.to_string()))?;
        let Some((id, name, content, created, updated, source)) = row else {
            return Err(KubeConfigError::NotFound { id });
        };
        let mut item = wire_summary(&id, &name, false, &created, &updated, source);
        if reveal_content {
            let plain = decrypt_kube_config_content(&self.vault, &content).map_err(map_vault_err)?;
            item["configContent"] = json!(plain);
        } else {
            item["hasConfigContent"] = json!(!content.trim().is_empty());
        }
        Ok(json!({ "kubeconfig": item }))
    }

    pub fn create(&self, params: &Map<String, Value>) -> Result<Value, KubeConfigError> {
        let name = params
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        if name.is_empty() {
            return Err(KubeConfigError::NameEmpty);
        }
        let content = params
            .get("configContent")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if content.is_empty() {
            return Err(KubeConfigError::ContentEmpty);
        }
        let stored = encrypt_kube_config_content(&self.vault, &content).map_err(map_vault_err)?;
        let id = new_uppercase_uuid();
        let now = now_grdb_datetime();
        let source = params
            .get("sourceFilePath")
            .and_then(|v| v.as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string);
        let conn = self.conn.lock().map_err(|_| io_err("lock poisoned"))?;
        conn.execute(
            "INSERT INTO kube_config (id, name, configContent, createdAt, updatedAt, sourceFilePath) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            (
                &id,
                name,
                &stored,
                &now,
                &now,
                source.as_deref(),
            ),
        )
        .map_err(|e| io_err(&e.to_string()))?;
        drop(conn);
        self.materialize(&id, &content)?;
        self.get(&id, false)
    }

    pub fn update(&self, params: &Map<String, Value>) -> Result<Value, KubeConfigError> {
        let id = normalize_id(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or(KubeConfigError::NotFound { id: "".into() })?,
        )?;
        if id == DEFAULT_ID {
            return Err(KubeConfigError::DefaultImmutable);
        }
        let conn = self.conn.lock().map_err(|_| io_err("lock poisoned"))?;
        if !kube_exists(&conn, &id)? {
            return Err(KubeConfigError::NotFound { id });
        }
        let mut sets = Vec::new();
        let mut name = None;
        let mut content = None;
        let mut source = None;
        if let Some(n) = params.get("name").and_then(|v| v.as_str()) {
            let t = n.trim();
            if t.is_empty() {
                return Err(KubeConfigError::NameEmpty);
            }
            name = Some(t.to_string());
            sets.push("name");
        }
        if let Some(c) = params.get("configContent").and_then(|v| v.as_str()) {
            let t = c.trim();
            if t.is_empty() {
                return Err(KubeConfigError::ContentEmpty);
            }
            let enc = encrypt_kube_config_content(&self.vault, t).map_err(map_vault_err)?;
            content = Some(enc);
            sets.push("configContent");
        }
        if params.contains_key("sourceFilePath") {
            source = params
                .get("sourceFilePath")
                .and_then(|v| v.as_str())
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string);
            sets.push("sourceFilePath");
        }
        if sets.is_empty() {
            return self.get(&id, false);
        }
        let now = now_grdb_datetime();
        let name_ref = name.as_deref();
        let content_ref = content.as_deref();
        conn.execute(
            "UPDATE kube_config SET name = COALESCE(?2, name), configContent = COALESCE(?3, configContent), updatedAt = ?4, sourceFilePath = CASE WHEN ?5 IS NOT NULL THEN ?5 ELSE sourceFilePath END WHERE id = ?1",
            (
                &id,
                name_ref,
                content_ref,
                &now,
                source.as_deref(),
            ),
        )
        .map_err(|e| io_err(&e.to_string()))?;
        drop(conn);
        if let Some(c) = &content {
            let plain = decrypt_kube_config_content(&self.vault, c).map_err(map_vault_err)?;
            self.materialize(&id, &plain)?;
        }
        self.get(&id, false)
    }

    pub fn delete(&self, id: &str) -> Result<Value, KubeConfigError> {
        let id = normalize_id(id)?;
        if id == DEFAULT_ID {
            return Err(KubeConfigError::DefaultImmutable);
        }
        let conn = self.conn.lock().map_err(|_| io_err("lock poisoned"))?;
        let n = conn
            .execute("DELETE FROM kube_config WHERE id = ?1", [&id])
            .map_err(|e| io_err(&e.to_string()))?;
        if n == 0 {
            return Err(KubeConfigError::NotFound { id });
        }
        drop(conn);
        let path = self.material_path(&id);
        let _ = std::fs::remove_file(path);
        Ok(json!({ "deleted": true, "id": id }))
    }

    pub fn contexts(&self, id: &str) -> Result<Value, KubeConfigError> {
        let yaml = self.plain_yaml(id)?;
        Ok(parse_kube_contexts(&yaml))
    }

    pub fn plain_yaml(&self, id: &str) -> Result<String, KubeConfigError> {
        let id = normalize_id(id)?;
        if id == DEFAULT_ID {
            return default_plain_yaml(&self.settings);
        }
        let conn = self.conn.lock().map_err(|_| io_err("lock poisoned"))?;
        let content: String = conn
            .query_row(
                "SELECT configContent FROM kube_config WHERE id = ?1",
                [&id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| io_err(&e.to_string()))?
            .ok_or(KubeConfigError::NotFound { id })?;
        decrypt_kube_config_content(&self.vault, &content).map_err(map_vault_err)
    }

    pub fn material_path(&self, id: &str) -> PathBuf {
        self.data_dir.join("kubeconfigs").join(format!("{id}.yaml"))
    }

    fn materialize(&self, id: &str, content: &str) -> Result<(), KubeConfigError> {
        let dir = self.data_dir.join("kubeconfigs");
        std::fs::create_dir_all(&dir).map_err(|e| io_err(&e.to_string()))?;
        let path = self.material_path(id);
        std::fs::write(&path, content).map_err(|e| io_err(&e.to_string()))?;
        set_path_mode(&path, 0o600).map_err(|e| io_err(&e.to_string()))?;
        set_path_mode(&dir, 0o700).ok();
        Ok(())
    }
}

fn wire_summary(
    id: &str,
    name: &str,
    is_default: bool,
    created: &str,
    updated: &str,
    source: Option<String>,
) -> Value {
    json!({
        "id": id,
        "name": name,
        "isDefault": is_default,
        "createdAt": created,
        "updatedAt": updated,
        "sourceFilePath": source,
    })
}

fn default_entry(settings: &SettingsStore) -> Result<Value, KubeConfigError> {
    let source = default_source_path(settings)?;
    let now = now_grdb_datetime();
    Ok(wire_summary(
        DEFAULT_ID,
        "Default",
        true,
        &now,
        &now,
        Some(source.display().to_string()),
    ))
}

fn default_source_path(settings: &SettingsStore) -> Result<PathBuf, KubeConfigError> {
    if let Ok(v) = settings.get("kuma.settings.customKubeconfigPath") {
        if let Some(p) = v.get("value").and_then(|x| x.as_str()) {
            let t = p.trim();
            if !t.is_empty() {
                return Ok(expand_tilde(t));
            }
        }
    }
    Ok(expand_tilde("~/.kube/config"))
}

fn default_plain_yaml(settings: &SettingsStore) -> Result<String, KubeConfigError> {
    let path = default_source_path(settings)?;
    Ok(std::fs::read_to_string(&path).unwrap_or_default())
}

fn expand_tilde(p: &str) -> PathBuf {
    if let Some(rest) = p.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(p)
}

fn parse_kube_contexts(yaml: &str) -> Value {
    let mut contexts = Vec::new();
    let mut current_ctx = String::new();
    for line in yaml.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("current-context:") {
            current_ctx = rest.trim().to_string();
        } else if let Some(rest) = t.strip_prefix("- name:") {
            contexts.push(json!({ "name": rest.trim() }));
        }
    }
    json!({
        "contexts": contexts,
        "currentContext": current_ctx,
    })
}

#[cfg(unix)]
fn set_path_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn set_path_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    let _ = (path, mode);
    Ok(())
}

fn normalize_id(id: &str) -> Result<String, KubeConfigError> {
    let t = id.trim();
    Uuid::parse_str(&t.to_lowercase())
        .map(|u| u.hyphenated().to_string().to_uppercase())
        .map_err(|_| KubeConfigError::NotFound { id: t.to_string() })
}

fn kube_exists(conn: &Connection, id: &str) -> Result<bool, KubeConfigError> {
    let n: i64 = conn
        .query_row(
            "SELECT COUNT(1) FROM kube_config WHERE id = ?1",
            [id],
            |row| row.get(0),
        )
        .map_err(|e| io_err(&e.to_string()))?;
    Ok(n > 0)
}

fn map_vault_err(e: kuma_domain::StoreError) -> KubeConfigError {
    KubeConfigError::Io {
        detail: e.to_string(),
    }
}

fn io_err(detail: &str) -> KubeConfigError {
    KubeConfigError::Io {
        detail: detail.into(),
    }
}
