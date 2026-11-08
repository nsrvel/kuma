use crate::service::service_row;
use kuma_domain::ServiceError;
use kuma_exec::check_port;
use rusqlite::Connection;
use serde_json::{json, Value};

pub fn service_preflight(conn: &Connection, service_id: &str) -> Result<Value, ServiceError> {
    let service = service_row(conn, service_id)?;
    let name = service
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let mut issues = Vec::new();
    if name.is_empty() {
        issues.push(json!({
            "code": "KUMA_SVC_NAME_EMPTY",
            "message": "Name cannot be empty",
        }));
    }
    let providers = service
        .get("providers")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    if providers == 0 {
        issues.push(json!({
            "code": "KUMA_SVC_LAST_PROVIDER",
            "message": "Service has no provider",
        }));
    }
    let active = service.get("activeProviderID");
    if active.map(|v| v.is_null()).unwrap_or(true) && providers > 0 {
        issues.push(json!({
            "code": "KUMA_SVC_PROVIDER_NOT_FOUND",
            "message": "Active provider not set",
        }));
    }
    if let Some(active) = service.get("activeProviderID").and_then(|v| v.as_str()) {
        if let Ok(providers) = provider_list(conn, active) {
            if let Some(ptype) = providers.get("type").and_then(|v| v.as_str()) {
                if ptype == "shell" {
                    let cmd = providers
                        .get("runCommand")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .trim();
                    if cmd.is_empty() {
                        issues.push(json!({
                            "code": "KUMA_PRV_SHELL_COMMAND",
                            "message": "Shell provider missing runCommand",
                        }));
                    }
                }
                if ptype == "ssh" {
                    let host = providers
                        .get("sshHost")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .trim();
                    if host.is_empty() {
                        issues.push(json!({
                            "code": "KUMA_PRV_SSH_HOST",
                            "message": "SSH provider missing sshHost",
                        }));
                    }
                }
            }
        }
    }
    if let Some(mappings) = service
        .get("portMappings")
        .and_then(|v| v.as_array())
    {
        for m in mappings {
            let port = m.get("localPort").and_then(|v| v.as_u64()).unwrap_or(0) as u16;
            if port == 0 {
                continue;
            }
            let probe = check_port(port);
            if probe.get("occupied").and_then(|v| v.as_bool()) == Some(true) {
                issues.push(json!({
                    "code": "KUMA_EXE_PORT_IN_USE",
                    "message": format!("Port {port} is already in use"),
                    "localPort": port,
                }));
            }
        }
    }
    Ok(json!({
        "ok": issues.is_empty(),
        "issues": issues,
    }))
}

fn provider_list(conn: &Connection, provider_id: &str) -> Result<Value, ServiceError> {
    let mut stmt = conn
        .prepare(
            "SELECT type, runCommand, sshHost FROM provider WHERE id = ?1",
        )
        .map_err(|e| ServiceError::InvalidPort {
            message: e.to_string(),
        })?;
    stmt.query_row([provider_id], |row| {
        Ok(json!({
            "type": row.get::<_, String>(0)?,
            "runCommand": row.get::<_, Option<String>>(1)?,
            "sshHost": row.get::<_, Option<String>>(2)?,
        }))
    })
    .map_err(|_| ServiceError::ProviderNotFound {
        id: provider_id.into(),
    })
}
