use crate::service::service_row;
use crate::validation::configuration_issues;
use kuma_domain::ServiceError;
use kuma_exec::check_port;
use rusqlite::Connection;
use serde_json::{json, Value};

#[allow(clippy::type_complexity)]
fn overlay_provider_validation_fields(
    conn: &Connection,
    provider_id: &str,
    provider: &mut Value,
) -> Result<(), ServiceError> {
    let (
        target,
        pattern,
        kube_ctx,
        kube_ns,
        kid,
        yaml,
        compose,
        run_cmd,
        workdir,
        http_url,
        tunnel_url,
        monitor,
    ): (
        Option<String>,
        Option<bool>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = conn
        .query_row(
            "SELECT targetName, usePattern, kubeContext, kubeNamespace, kubeConfigID, yamlConfig, composeFilePath, runCommand, workingDirectory, httpCheckUrl, tunnelTargetUrl, monitorProcessName FROM provider WHERE id = ?1",
            [provider_id],
            |r| {
                Ok((
                    r.get(0)?,
                    r.get(1)?,
                    r.get(2)?,
                    r.get(3)?,
                    r.get(4)?,
                    r.get(5)?,
                    r.get(6)?,
                    r.get(7)?,
                    r.get(8)?,
                    r.get(9)?,
                    r.get(10)?,
                    r.get(11)?,
                ))
            },
        )
        .map_err(|_| ServiceError::ProviderNotFound {
            id: provider_id.into(),
        })?;
    let Some(obj) = provider.as_object_mut() else {
        return Ok(());
    };
    for (key, val) in [
        ("targetName", target.map(Value::String)),
        ("usePattern", pattern.map(Value::Bool)),
        ("kubeContext", kube_ctx.map(Value::String)),
        ("kubeNamespace", kube_ns.map(Value::String)),
        ("kubeConfigID", kid.map(Value::String)),
        ("yamlConfig", yaml.map(Value::String)),
        ("composeFilePath", compose.map(Value::String)),
        ("runCommand", run_cmd.map(Value::String)),
        ("workingDirectory", workdir.map(Value::String)),
        ("httpCheckUrl", http_url.map(Value::String)),
        ("tunnelTargetUrl", tunnel_url.map(Value::String)),
        ("monitorProcessName", monitor.map(Value::String)),
    ] {
        if let Some(v) = val {
            obj.insert(key.into(), v);
        }
    }
    Ok(())
}

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
    let active_id = service
        .get("activeProviderID")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let Some(active_id) = active_id else {
        issues.push(json!({
            "code": "KUMA_SVC_PROVIDER_NOT_FOUND",
            "message": "Active provider not set",
            "severity": "blocking",
        }));
        return Ok(json!({ "ok": false, "issues": issues }));
    };
    if !providers
        .iter()
        .any(|p| p.get("id").and_then(|v| v.as_str()) == Some(active_id))
    {
        issues.push(json!({
            "code": "KUMA_SVC_PROVIDER_NOT_FOUND",
            "message": "Active provider not set",
            "severity": "blocking",
        }));
        return Ok(json!({ "ok": false, "issues": issues }));
    }
    let mut provider = crate::provider::provider_by_id(conn, active_id)?;
    overlay_provider_validation_fields(conn, active_id, &mut provider)?;
    let ports = service
        .get("portMappings")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let auth_key = provider
        .get("sshPassword")
        .map(|v| v.is_null())
        .unwrap_or(true);
    issues.extend(configuration_issues(&provider, &ports, auth_key));
    if provider.get("type").and_then(|v| v.as_str()) == Some("kubernetes") {
        let target = provider
            .get("targetName")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        let pattern = provider
            .get("usePattern")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        if pattern || target.contains('*') {
            issues.push(json!({
                "code": "k8s.target_resolve",
                "message": "Pattern target not verified against live cluster",
                "severity": "warning",
            }));
        }
    }
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

    #[test]
    fn dt_preflight_k8s_pattern_warning() {
        let dir = tempfile::tempdir().unwrap();
        let store = StoreHandle::open(dir.path()).unwrap();
        let ws = store.workspace().list().unwrap()[0]["id"]
            .as_str()
            .unwrap()
            .to_string();
        let mut create = Map::new();
        create.insert("workspaceID".into(), json!(ws));
        create.insert("name".into(), json!("pf-k8s"));
        let svc = store.service().create(&create).unwrap();
        let sid = svc["id"].as_str().unwrap();
        let plist = store.provider().list(sid).unwrap();
        let pid = plist["providers"][0]["id"].as_str().unwrap();
        let mut p = Map::new();
        p.insert("id".into(), json!(pid));
        p.insert("type".into(), json!("kubernetes"));
        p.insert("kubeConfigID".into(), json!(crate::kubeconfig::DEFAULT_ID));
        p.insert("kubeContext".into(), json!("ctx"));
        p.insert("targetName".into(), json!("redis-*"));
        p.insert("usePattern".into(), json!(true));
        store.provider().update(store.vault(), &p).unwrap();
        let mut sw = Map::new();
        sw.insert("id".into(), json!(sid));
        sw.insert("providerID".into(), json!(pid));
        store.service().switch_provider(&sw).unwrap();
        let mut ports = Map::new();
        ports.insert("serviceID".into(), json!(sid));
        ports.insert("providerID".into(), json!(pid));
        ports.insert(
            "ports".into(),
            json!([{"localPort": 18081, "remotePort": 8081}]),
        );
        store.provider().set_ports(&ports).unwrap();
        let mut pre = Map::new();
        pre.insert("id".into(), json!(sid));
        let out = store.service().preflight(&pre).unwrap();
        assert!(out["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|i| i["code"] == "k8s.target_resolve"));
    }
}
