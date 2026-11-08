use kuma_domain::ServiceError;
use rusqlite::Connection;
use serde_json::{Map, Value};

const SSH_FIELDS: &[&str] = &["sshHost", "sshUser", "sshPort", "sshKeyPath", "sshPassword"];
const KUBE_FIELDS: &[&str] = &[
    "kubeConfigID",
    "kubeContext",
    "kubeNamespace",
    "targetName",
    "kubeTargetType",
    "usePattern",
    "yamlConfig",
];
const SHELL_FIELDS: &[&str] = &["runCommand", "workingDirectory"];

pub fn reject_foreign_fields(ptype: &str, params: &Map<String, Value>) -> Result<(), ServiceError> {
    for (key, _) in params {
        if matches!(key.as_str(), "id" | "type" | "label" | "expectedUpdatedAt") {
            continue;
        }
        if ptype == "shell" && (SSH_FIELDS.contains(&key.as_str()) || KUBE_FIELDS.contains(&key.as_str()))
        {
            return Err(ServiceError::InvalidPort {
                message: format!("KUMA_PRV_FIELD_NOT_APPLICABLE: {key} does not apply to shell"),
            });
        }
        if ptype == "ssh" && (SHELL_FIELDS.contains(&key.as_str()) || KUBE_FIELDS.contains(&key.as_str()))
        {
            return Err(ServiceError::InvalidPort {
                message: format!("KUMA_PRV_FIELD_NOT_APPLICABLE: {key} does not apply to ssh"),
            });
        }
        if ptype == "kubernetes"
            && (SSH_FIELDS.contains(&key.as_str()) || SHELL_FIELDS.contains(&key.as_str()))
        {
            return Err(ServiceError::InvalidPort {
                message: format!("KUMA_PRV_FIELD_NOT_APPLICABLE: {key} does not apply to kubernetes"),
            });
        }
    }
    Ok(())
}

pub fn ports_applicable(ptype: &str) -> bool {
    ptype == "kubernetes" || ptype == "ssh"
}

pub fn normalize_label(label: Option<&str>) -> Option<String> {
    label.map(str::trim).and_then(|s| {
        if s.is_empty() {
            None
        } else {
            Some(s.to_string())
        }
    })
}

pub fn check_source_conflict(params: &Map<String, Value>) -> Result<(), ServiceError> {
    let compose = params
        .get("composeFilePath")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let yaml = params
        .get("yamlConfig")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if compose.is_some() && yaml.is_some() {
        return Err(ServiceError::InvalidPort {
            message: "KUMA_PRV_SOURCE_CONFLICT: composeFilePath and yamlConfig".into(),
        });
    }
  let script_path = params
        .get("initialScriptPath")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let script_inline = params
        .get("initialScript")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if script_path.is_some() && script_inline.is_some() {
        return Err(ServiceError::InvalidPort {
            message: "KUMA_PRV_SOURCE_CONFLICT: initialScriptPath and initialScript".into(),
        });
    }
    Ok(())
}

/// After patch, enforce compose/yaml and script exclusivity on stored row (INV-D-PRV-07).
pub fn enforce_stored_exclusivity(conn: &Connection, id: &str, now: &str) -> Result<(), ServiceError> {
    let row: (Option<String>, Option<String>, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT composeFilePath, yamlConfig, initialScriptPath, initialScript FROM provider WHERE id = ?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    let (compose, yaml, script_path, script_inline) = row;
    let c = compose.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let y = yaml.as_deref().map(str::trim).filter(|s| !s.is_empty());
    if c.is_some() && y.is_some() {
        conn.execute(
            "UPDATE provider SET yamlConfig = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    } else if y.is_some() {
        conn.execute(
            "UPDATE provider SET composeFilePath = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    } else if c.is_some() {
        conn.execute(
            "UPDATE provider SET yamlConfig = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    }
    let sp = script_path.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let si = script_inline.as_deref().map(str::trim).filter(|s| !s.is_empty());
    if sp.is_some() && si.is_some() {
        conn.execute(
            "UPDATE provider SET initialScript = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    } else if si.is_some() {
        conn.execute(
            "UPDATE provider SET initialScriptPath = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    } else if sp.is_some() {
        conn.execute(
            "UPDATE provider SET initialScript = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    }
    Ok(())
}
