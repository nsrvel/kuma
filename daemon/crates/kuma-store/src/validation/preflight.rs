use crate::service::service_row;
use crate::validation::configuration_issues;
use kuma_domain::ServiceError;
use kuma_exec::check_port;
use rusqlite::Connection;
use serde_json::{json, Value};

pub fn service_preflight(conn: &Connection, service_id: &str) -> Result<Value, ServiceError> {
    let service = service_row(conn, service_id)?;
    if service.get("isDisabled").and_then(|v| v.as_bool()) == Some(true) {
        return Ok(json!({
            "ok": true,
            "serviceDisabled": true,
            "issues": [],
        }));
    }
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
            "severity": "blocking",
        }));
    }
    let providers = service
        .get("providers")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if providers.is_empty() {
        issues.push(json!({
            "code": "provider.missing",
            "message": "Add a provider before starting this service.",
            "severity": "blocking",
        }));
        return Ok(json!({ "ok": false, "issues": issues }));
    }
    let active_id = service.get("activeProviderID").and_then(|v| v.as_str());
    let provider = active_id.and_then(|id| {
        providers
            .iter()
            .find(|p| p.get("id").and_then(|v| v.as_str()) == Some(id))
    });
    let Some(provider) = provider else {
        issues.push(json!({
            "code": "KUMA_SVC_PROVIDER_NOT_FOUND",
            "message": "Active provider not set",
            "severity": "blocking",
        }));
        return Ok(json!({ "ok": false, "issues": issues }));
    };
    let ports = service
        .get("portMappings")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let auth_key = provider
        .get("sshPassword")
        .map(|v| v.is_null())
        .unwrap_or(true);
    issues.extend(configuration_issues(provider, &ports, auth_key));
    for m in &ports {
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
                "severity": "blocking",
            }));
        }
    }
    let ok = issues.is_empty();
    Ok(json!({
        "ok": ok,
        "issues": issues,
    }))
}

#[cfg(test)]
mod tests {
    use crate::StoreHandle;
    use serde_json::{json, Map};

    #[test]
    fn dt_preflight_disabled_service_ok() {
        let dir = tempfile::tempdir().unwrap();
        let store = StoreHandle::open(dir.path()).unwrap();
        let ws = store.workspace().list().unwrap()[0]["id"]
            .as_str()
            .unwrap()
            .to_string();
        let mut create = Map::new();
        create.insert("workspaceID".into(), json!(ws));
        create.insert("name".into(), json!("pf"));
        let svc = store.service().create(&create).unwrap();
        let sid = svc["id"].as_str().unwrap();
        let mut dis = Map::new();
        dis.insert("id".into(), json!(sid));
        dis.insert("disabled".into(), json!(true));
        store.service().set_disabled(&dis).unwrap();
        let mut pre = Map::new();
        pre.insert("id".into(), json!(sid));
        let out = store.service().preflight(&pre).unwrap();
        assert_eq!(out["serviceDisabled"], true);
    }

    #[test]
    fn dt_preflight_shell_provider() {
        let dir = tempfile::tempdir().unwrap();
        let store = StoreHandle::open(dir.path()).unwrap();
        let ws = store.workspace().list().unwrap()[0]["id"]
            .as_str()
            .unwrap()
            .to_string();
        let mut create = Map::new();
        create.insert("workspaceID".into(), json!(ws));
        create.insert("name".into(), json!("pf2"));
        let svc = store.service().create(&create).unwrap();
        let sid = svc["id"].as_str().unwrap();
        let plist = store.provider().list(sid).unwrap();
        let pid = plist["providers"][0]["id"].as_str().unwrap();
        let mut p = Map::new();
        p.insert("id".into(), json!(pid));
        p.insert("type".into(), json!("shell"));
        p.insert("runCommand".into(), json!("echo ok"));
        store.provider().update(store.vault(), &p).unwrap();
        let mut pre = Map::new();
        pre.insert("id".into(), json!(sid));
        let out = store.service().preflight(&pre).unwrap();
        assert_eq!(out["ok"], true);
    }
}
