use crate::sec::wire::{encrypt_provider_secret, provider_for_runner, redact_provider};
use crate::seed::{new_uppercase_uuid, now_grdb_datetime};
use crate::service::{
    effective_active_provider, provider_row_to_json, service_row, ProviderStoreHelper,
};
use crate::Vault;
use kuma_domain::ServiceError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Map, Value};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone)]
pub struct ProviderStore {
    conn: Arc<Mutex<Connection>>,
}

impl ProviderStore {
    pub fn new(conn: Arc<Mutex<Connection>>) -> Self {
        Self { conn }
    }

    pub fn get(&self, id: &str) -> Result<Value, ServiceError> {
        let id = normalize_uuid(id)?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        Ok(redact_provider(provider_by_id(&conn, &id)?))
    }

    pub fn get_for_exec(&self, id: &str, vault: &Vault) -> Result<Value, ServiceError> {
        let id = normalize_uuid(id)?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        let mut v = provider_by_id(&conn, &id)?;
        merge_provider_secrets(&conn, &id, &mut v)?;
        provider_for_runner(vault, v, true).map_err(map_store_err)
    }

    pub fn list(&self, service_id: &str) -> Result<Value, ServiceError> {
        let sid = normalize_uuid(service_id)?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &sid)? {
            return Err(ServiceError::NotFound { id: sid });
        }
        let mut stmt = conn
            .prepare(
                "SELECT id, serviceID, type, label, kubeConfigID, kubeContext, kubeNamespace, targetName, kubeTargetType, usePattern, yamlConfig, initialScript, runCommand, workingDirectory, sshHost, sshUser, sshPort, sshKeyPath, sshPassword, httpCheckUrl, httpCheckInterval, tunnelType, tunnelTargetUrl, ngrokAuthToken, monitorProcessName, monitorInterval, createdAt, updatedAt, customKubeConfigPath, composeFilePath, initialScriptPath, autoReconnect FROM provider WHERE serviceID = ?1 ORDER BY createdAt ASC, rowid ASC",
            )
            .map_err(|e| io_err(&e.to_string()))?;
        let rows = stmt
            .query_map([&sid], ProviderStoreHelper::read_row)
            .map_err(|e| io_err(&e.to_string()))?;
        let mut providers = Vec::new();
        for row in rows {
            providers.push(redact_provider(provider_row_to_json(
                &row.map_err(|e| io_err(&e.to_string()))?,
            )));
        }
        let active = effective_active_provider(&conn, &sid)?;
        Ok(json!({
            "providers": providers,
            "activeProviderID": active,
        }))
    }

    pub fn add(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let sid = normalize_uuid(
            params
                .get("serviceID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &sid)? {
            return Err(ServiceError::NotFound { id: sid });
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_service_stale(&conn, &sid, exp)?;
        }
        let provider_obj = params
            .get("provider")
            .and_then(|v| v.as_object())
            .ok_or_else(|| ServiceError::InvalidPort {
                message: "missing provider".into(),
            })?;
        let ptype = provider_obj
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("docker");
        let label = provider_obj.get("label").and_then(|v| v.as_str());
        let id = new_uppercase_uuid();
        let now = now_grdb_datetime();
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| io_err(&e.to_string()))?;
        tx.execute(
            "INSERT INTO provider (id, serviceID, type, label, createdAt, updatedAt, autoReconnect) VALUES (?1,?2,?3,?4,?5,?6,0)",
            rusqlite::params![id, sid, ptype, label, now, now],
        )
        .map_err(|e| io_err(&e.to_string()))?;
        tx.execute(
            "UPDATE service SET activeProviderID = ?1, updatedAt = ?2 WHERE id = ?3",
            rusqlite::params![id, now, sid],
        )
        .map_err(|e| io_err(&e.to_string()))?;
        tx.commit().map_err(|e| io_err(&e.to_string()))?;
        let provider = provider_by_id(&conn, &id)?;
        let service = service_row(&conn, &sid)?;
        Ok(json!({
            "provider": provider,
            "service": service,
            "activeProviderID": id,
        }))
    }

    pub fn update(
        &self,
        vault: &Vault,
        params: &Map<String, Value>,
    ) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::ProviderNotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        let row = provider_by_id_raw(&conn, &id)?;
        for key in ["serviceID", "createdAt"] {
            if params.get(key).is_some() {
                return Err(ServiceError::FieldReadonly { field: key.into() });
            }
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_provider_stale(&conn, &id, exp)?;
        }
        let now = now_grdb_datetime();
        let ptype = params
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or(&row.type_);
        crate::validation::reject_foreign_fields(ptype, params)?;
        crate::validation::check_source_conflict(params)?;
        let label = crate::validation::normalize_label(
            params
                .get("label")
                .and_then(|v| v.as_str())
                .or(row.label.as_deref()),
        );
        conn.execute(
            "UPDATE provider SET type = ?1, label = ?2, updatedAt = ?3 WHERE id = ?4",
            rusqlite::params![ptype, label, now, id],
        )
        .map_err(|e| io_err(&e.to_string()))?;
        apply_provider_patch(&conn, vault, &id, params, &now)?;
        Ok(json!({ "provider": redact_provider(provider_by_id(&conn, &id)?) }))
    }

    pub fn delete(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::ProviderNotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        let row = provider_by_id_raw(&conn, &id)?;
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_service_stale(&conn, &row.service_id, exp)?;
        }
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM provider WHERE serviceID = ?1",
                [&row.service_id],
                |r| r.get(0),
            )
            .map_err(|e| io_err(&e.to_string()))?;
        if count <= 1 {
            return Err(ServiceError::LastProvider);
        }
        let active = effective_active_provider(&conn, &row.service_id)?;
        let was_active = active.as_deref() == Some(id.as_str());
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| io_err(&e.to_string()))?;
        tx.execute("DELETE FROM provider WHERE id = ?1", [&id])
            .map_err(|e| io_err(&e.to_string()))?;
        let mut new_active = active;
        if was_active {
            new_active = tx
                .query_row(
                    "SELECT id FROM provider WHERE serviceID = ?1 ORDER BY createdAt ASC, rowid ASC LIMIT 1",
                    [&row.service_id],
                    |r| r.get::<_, String>(0),
                )
                .optional()
                .map_err(|e| io_err(&e.to_string()))?;
            let now = now_grdb_datetime();
            tx.execute(
                "UPDATE service SET activeProviderID = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![new_active, now, row.service_id],
            )
            .map_err(|e| io_err(&e.to_string()))?;
        }
        tx.commit().map_err(|e| io_err(&e.to_string()))?;
        Ok(json!({
            "deleted": true,
            "activeProviderID": new_active,
        }))
    }

    pub fn set_ports(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let sid = normalize_uuid(
            params
                .get("serviceID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let pid = normalize_uuid(
            params
                .get("providerID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::ProviderNotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &sid)? {
            return Err(ServiceError::NotFound { id: sid });
        }
        let prov_sid: String = conn
            .query_row(
                "SELECT serviceID FROM provider WHERE id = ?1",
                [&pid],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| io_err(&e.to_string()))?
            .ok_or_else(|| ServiceError::ProviderNotFound { id: pid.clone() })?;
        if prov_sid != sid {
            return Err(ServiceError::ProviderNotFound { id: pid });
        }
        let ptype: String = conn
            .query_row("SELECT type FROM provider WHERE id = ?1", [&pid], |r| {
                r.get(0)
            })
            .map_err(|e| io_err(&e.to_string()))?;
        let ports = params
            .get("ports")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        if !ports.is_empty() && !crate::validation::ports_applicable(&ptype) {
            return Err(ServiceError::InvalidPort {
                message: "KUMA_PRV_PORTS_NOT_APPLICABLE".into(),
            });
        }
        for (i, row) in ports.iter().enumerate() {
            let local = row.get("localPort").and_then(|v| v.as_i64());
            let remote = row.get("remotePort").and_then(|v| v.as_i64());
            let valid = |p: Option<i64>| p.map(|n| (1..=65535).contains(&n)).unwrap_or(false);
            if !valid(local) || !valid(remote) {
                return Err(ServiceError::InvalidPort {
                    message: format!(
                        "Port row {}: enter local and remote ports (1\u{2013}65535).",
                        i + 1
                    ),
                });
            }
        }
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| io_err(&e.to_string()))?;
        tx.execute(
            "DELETE FROM portMapping WHERE serviceID = ?1 AND providerID = ?2",
            rusqlite::params![sid, pid],
        )
        .map_err(|e| io_err(&e.to_string()))?;
        for row in &ports {
            let local = row.get("localPort").and_then(|v| v.as_i64()).unwrap();
            let remote = row.get("remotePort").and_then(|v| v.as_i64()).unwrap();
            let protocol = row
                .get("protocolType")
                .and_then(|v| v.as_str())
                .unwrap_or("TCP");
            let map_id = row
                .get("id")
                .and_then(|v| v.as_str())
                .map(|s| normalize_uuid(s).unwrap_or_else(|_| new_uppercase_uuid()))
                .unwrap_or_else(new_uppercase_uuid);
            tx.execute(
                "INSERT INTO portMapping (id, serviceID, localPort, remotePort, protocolType, providerID) VALUES (?1,?2,?3,?4,?5,?6)",
                rusqlite::params![map_id, sid, local, remote, protocol, pid],
            )
            .map_err(|e| io_err(&e.to_string()))?;
        }
        tx.commit().map_err(|e| io_err(&e.to_string()))?;
        let mappings = port_mappings_for_provider(&conn, &sid, &pid)?;
        Ok(json!({ "portMappings": mappings }))
    }
}

pub(crate) struct ProviderRow {
    pub service_id: String,
    pub type_: String,
    pub label: Option<String>,
}

fn provider_by_id_raw(conn: &Connection, id: &str) -> Result<ProviderRow, ServiceError> {
    conn.query_row(
        "SELECT serviceID, type, label FROM provider WHERE id = ?1",
        [id],
        |r| {
            Ok(ProviderRow {
                service_id: r.get(0)?,
                type_: r.get(1)?,
                label: r.get(2)?,
            })
        },
    )
    .optional()
    .map_err(|e| io_err(&e.to_string()))?
    .ok_or_else(|| ServiceError::ProviderNotFound { id: id.into() })
}

fn enrich_provider_from_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<Value> {
    let row = ProviderStoreHelper::read_row(r)?;
    let mut v = provider_row_to_json(&row);
    let Some(obj) = v.as_object_mut() else {
        return Ok(v);
    };
    merge_opt_str(obj, "kubeConfigID", r.get(4)?);
    merge_opt_str(obj, "kubeContext", r.get(5)?);
    merge_opt_str(obj, "kubeNamespace", r.get(6)?);
    merge_opt_str(obj, "targetName", r.get(7)?);
    merge_opt_str(obj, "kubeTargetType", r.get(8)?);
    if let Ok(pat) = r.get::<_, Option<i64>>(9) {
        obj.insert("usePattern".into(), json!(pat.unwrap_or(0) != 0));
    }
    merge_opt_str(obj, "yamlConfig", r.get(10)?);
    merge_opt_str(obj, "initialScript", r.get(11)?);
    merge_opt_str(obj, "sshHost", r.get(14)?);
    merge_opt_str(obj, "sshUser", r.get(15)?);
    merge_opt_str(obj, "sshKeyPath", r.get(17)?);
    merge_opt_str(obj, "httpCheckUrl", r.get(19)?);
    merge_opt_str(obj, "tunnelType", r.get(21)?);
    merge_opt_str(obj, "tunnelTargetUrl", r.get(22)?);
    merge_opt_str(obj, "monitorProcessName", r.get(24)?);
    merge_opt_str(obj, "composeFilePath", r.get(29)?);
    merge_opt_str(obj, "customKubeConfigPath", r.get(28)?);
    merge_opt_str(obj, "initialScriptPath", r.get(30)?);
    if let Ok(Some(p)) = r.get::<_, Option<i64>>(16) {
        obj.insert("sshPort".into(), json!(p));
    }
    if let Ok(Some(n)) = r.get::<_, Option<i64>>(20) {
        obj.insert("httpCheckInterval".into(), json!(n));
    }
    if let Ok(Some(n)) = r.get::<_, Option<i64>>(25) {
        obj.insert("monitorInterval".into(), json!(n));
    }
    Ok(v)
}

pub(crate) fn provider_by_id(conn: &Connection, id: &str) -> Result<Value, ServiceError> {
    conn.query_row(
        "SELECT id, serviceID, type, label, kubeConfigID, kubeContext, kubeNamespace, targetName, kubeTargetType, usePattern, yamlConfig, initialScript, runCommand, workingDirectory, sshHost, sshUser, sshPort, sshKeyPath, sshPassword, httpCheckUrl, httpCheckInterval, tunnelType, tunnelTargetUrl, ngrokAuthToken, monitorProcessName, monitorInterval, createdAt, updatedAt, customKubeConfigPath, composeFilePath, initialScriptPath, autoReconnect FROM provider WHERE id = ?1",
        [id],
        enrich_provider_from_row,
    )
    .map_err(|_| ServiceError::ProviderNotFound { id: id.into() })
}

fn merge_opt_str(obj: &mut serde_json::Map<String, Value>, key: &str, v: Option<String>) {
    if let Some(s) = v.filter(|s| !s.is_empty()) {
        obj.insert(key.into(), json!(s));
    }
}

fn port_mappings_for_provider(
    conn: &Connection,
    sid: &str,
    pid: &str,
) -> Result<Vec<Value>, ServiceError> {
    let mut stmt = conn
        .prepare(
            "SELECT id, serviceID, localPort, remotePort, protocolType, providerID FROM portMapping WHERE serviceID = ?1 AND providerID = ?2 ORDER BY rowid ASC",
        )
        .map_err(|e| io_err(&e.to_string()))?;
    let rows = stmt
        .query_map(rusqlite::params![sid, pid], |r| {
            Ok(json!({
                "id": r.get::<_, String>(0)?,
                "serviceID": r.get::<_, String>(1)?,
                "localPort": r.get::<_, i64>(2)?,
                "remotePort": r.get::<_, i64>(3)?,
                "protocolType": r.get::<_, String>(4)?,
                "providerID": r.get::<_, Option<String>>(5)?,
            }))
        })
        .map_err(|e| io_err(&e.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| io_err(&e.to_string()))
}

fn normalize_uuid(id: &str) -> Result<String, ServiceError> {
    Uuid::parse_str(id.trim())
        .map(|u| u.to_string().to_uppercase())
        .map_err(|_| ServiceError::NotFound { id: id.into() })
}

fn service_exists(conn: &Connection, id: &str) -> Result<bool, ServiceError> {
    Ok(conn
        .query_row("SELECT 1 FROM service WHERE id = ?1", [id], |_| Ok(()))
        .optional()
        .map_err(|e| io_err(&e.to_string()))?
        .is_some())
}

fn check_service_stale(conn: &Connection, id: &str, expected: &Value) -> Result<(), ServiceError> {
    let current: String = conn
        .query_row("SELECT updatedAt FROM service WHERE id = ?1", [id], |r| {
            r.get(0)
        })
        .map_err(|e| io_err(&e.to_string()))?;
    match expected {
        Value::String(s) if s == &current => Ok(()),
        _ => Err(ServiceError::ConflictStale),
    }
}

fn check_provider_stale(conn: &Connection, id: &str, expected: &Value) -> Result<(), ServiceError> {
    let current: String = conn
        .query_row("SELECT updatedAt FROM provider WHERE id = ?1", [id], |r| {
            r.get(0)
        })
        .map_err(|e| io_err(&e.to_string()))?;
    match expected {
        Value::String(s) if s == &current => Ok(()),
        _ => Err(ServiceError::ConflictStale),
    }
}

fn apply_provider_patch(
    conn: &Connection,
    vault: &Vault,
    id: &str,
    params: &Map<String, Value>,
    now: &str,
) -> Result<(), ServiceError> {
    crate::validation::check_source_conflict(params)?;
    patch_str(conn, id, now, params, "runCommand")?;
    patch_str(conn, id, now, params, "workingDirectory")?;
    patch_str(conn, id, now, params, "sshHost")?;
    patch_str(conn, id, now, params, "sshUser")?;
    patch_str(conn, id, now, params, "sshKeyPath")?;
    patch_str(conn, id, now, params, "httpCheckUrl")?;
    patch_str(conn, id, now, params, "tunnelType")?;
    patch_str(conn, id, now, params, "tunnelTargetUrl")?;
    patch_str(conn, id, now, params, "monitorProcessName")?;
    patch_str(conn, id, now, params, "composeFilePath")?;
    patch_str(conn, id, now, params, "initialScriptPath")?;
    patch_str(conn, id, now, params, "kubeContext")?;
    patch_str(conn, id, now, params, "kubeNamespace")?;
    patch_str(conn, id, now, params, "targetName")?;
    patch_str(conn, id, now, params, "kubeConfigID")?;
    if let Some(v) = params.get("usePattern").and_then(|v| v.as_bool()) {
        conn.execute(
            "UPDATE provider SET usePattern = ?1, updatedAt = ?2 WHERE id = ?3",
            rusqlite::params![v, now, id],
        )
        .map_err(|e| io_err(&e.to_string()))?;
    }
    patch_str(conn, id, now, params, "yamlConfig")?;
    patch_str(conn, id, now, params, "initialScript")?;
    if let Some(v) = params.get("sshPort") {
        if let Some(n) = v.as_i64() {
            conn.execute(
                "UPDATE provider SET sshPort = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![n, now, id],
            )
            .map_err(|e| io_err(&e.to_string()))?;
        }
    }
    if let Some(v) = params.get("autoReconnect").and_then(|v| v.as_bool()) {
        conn.execute(
            "UPDATE provider SET autoReconnect = ?1, updatedAt = ?2 WHERE id = ?3",
            rusqlite::params![v, now, id],
        )
        .map_err(|e| io_err(&e.to_string()))?;
    }
    if params.contains_key("sshPassword") {
        let enc = match params.get("sshPassword").and_then(|v| v.as_str()) {
            None | Some("") => String::new(),
            Some(p) => encrypt_provider_secret(vault, p).map_err(map_store_err)?,
        };
        conn.execute(
            "UPDATE provider SET sshPassword = ?1, updatedAt = ?2 WHERE id = ?3",
            rusqlite::params![enc, now, id],
        )
        .map_err(|e| io_err(&e.to_string()))?;
    }
    if params.contains_key("ngrokAuthToken") {
        let enc = match params.get("ngrokAuthToken").and_then(|v| v.as_str()) {
            None | Some("") => String::new(),
            Some(p) => encrypt_provider_secret(vault, p).map_err(map_store_err)?,
        };
        conn.execute(
            "UPDATE provider SET ngrokAuthToken = ?1, updatedAt = ?2 WHERE id = ?3",
            rusqlite::params![enc, now, id],
        )
        .map_err(|e| io_err(&e.to_string()))?;
    }
    crate::validation::enforce_stored_exclusivity(conn, id, now)
}

fn patch_str(
    conn: &Connection,
    id: &str,
    now: &str,
    params: &Map<String, Value>,
    column: &str,
) -> Result<(), ServiceError> {
    if !params.contains_key(column) {
        return Ok(());
    }
    let val = params
        .get(column)
        .and_then(|v| v.as_str())
        .map(str::to_string);
    let sql = format!("UPDATE provider SET {column} = ?1, updatedAt = ?2 WHERE id = ?3");
    conn.execute(&sql, rusqlite::params![val, now, id])
        .map_err(|e| io_err(&e.to_string()))?;
    Ok(())
}

fn merge_provider_secrets(conn: &Connection, id: &str, v: &mut Value) -> Result<(), ServiceError> {
    let (ssh, tok): (Option<String>, Option<String>) = conn
        .query_row(
            "SELECT sshPassword, ngrokAuthToken FROM provider WHERE id = ?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .map_err(|e| io_err(&e.to_string()))?;
    let Some(obj) = v.as_object_mut() else {
        return Ok(());
    };
    if let Some(s) = ssh.filter(|s| !s.is_empty()) {
        obj.insert("sshPassword".into(), json!(s));
    }
    if let Some(t) = tok.filter(|s| !s.is_empty()) {
        obj.insert("ngrokAuthToken".into(), json!(t));
    }
    Ok(())
}

fn map_store_err(e: kuma_domain::StoreError) -> ServiceError {
    ServiceError::InvalidPort {
        message: e.to_string(),
    }
}

fn lock_err() -> ServiceError {
    ServiceError::InvalidPort {
        message: "lock poisoned".into(),
    }
}

fn io_err(detail: &str) -> ServiceError {
    ServiceError::InvalidPort {
        message: detail.into(),
    }
}
