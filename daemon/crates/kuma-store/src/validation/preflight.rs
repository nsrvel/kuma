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
