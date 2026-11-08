use crate::kubeconfig::DEFAULT_ID;
use kuma_domain::ServiceError;
use rusqlite::{Connection, OptionalExtension, Row};
use serde_json::{json, Value};

pub struct ProviderStoreHelper;

pub struct ProviderRowData {
    pub id: String,
    pub service_id: String,
    pub type_: String,
    pub label: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub auto_reconnect: bool,
    pub run_command: Option<String>,
    pub working_directory: Option<String>,
    pub kube_config_id: Option<String>,
}

impl ProviderStoreHelper {
    pub fn read_row(r: &Row<'_>) -> rusqlite::Result<ProviderRowData> {
        Ok(ProviderRowData {
            id: r.get(0)?,
            service_id: r.get(1)?,
            type_: r.get(2)?,
            label: r.get(3)?,
            created_at: r.get(26)?,
            updated_at: r.get(27)?,
            auto_reconnect: r.get(31)?,
            run_command: r.get(12)?,
            working_directory: r.get(13)?,
            kube_config_id: r.get(4)?,
        })
    }
}

pub fn provider_row_to_json(row: &ProviderRowData) -> Value {
    let label_trim = row.label.as_deref().unwrap_or("").trim();
    let display = if label_trim.is_empty() {
        sidebar_label(&row.type_).to_string()
    } else {
        row.label.clone().unwrap_or_default()
    };
    let resolved = resolved_target(&row.type_, row.label.as_deref());
    let kube_config_id = row.kube_config_id.clone().or_else(|| {
        if row.type_ == "kubernetes" {
            Some(DEFAULT_ID.to_string())
        } else {
            None
        }
    });
    json!({
        "id": row.id,
        "serviceID": row.service_id,
        "type": row.type_,
        "label": row.label,
        "displayName": display,
        "resolvedTarget": resolved,
        "isAutoReconnectEnabled": row.auto_reconnect && supports_auto_reconnect(&row.type_),
        "createdAt": row.created_at,
        "updatedAt": row.updated_at,
        "runCommand": row.run_command,
        "workingDirectory": row.working_directory,
        "kubeConfigID": kube_config_id,
    })
}

pub fn effective_active_provider(
    conn: &Connection,
    service_id: &str,
) -> Result<Option<String>, ServiceError> {
    let stored: Option<String> = conn
        .query_row(
            "SELECT activeProviderID FROM service WHERE id = ?1",
            [service_id],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| map_db(&e.to_string()))?
        .flatten();
    if let Some(id) = stored {
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM provider WHERE id = ?1",
                [&id],
                |_| Ok(()),
            )
            .optional()
            .map_err(|e| map_db(&e.to_string()))?
            .is_some();
        if exists {
            return Ok(Some(id));
        }
    }
    conn.query_row(
        "SELECT id FROM provider WHERE serviceID = ?1 ORDER BY createdAt ASC, rowid ASC LIMIT 1",
        [service_id],
        |r| r.get::<_, String>(0),
    )
    .optional()
    .map_err(|e| map_db(&e.to_string()))
}

#[allow(clippy::type_complexity)]
pub fn service_row(conn: &Connection, id: &str) -> Result<Value, ServiceError> {
    let (workspace_id, name, icon, color, desc, _active, disabled, starred, created, updated): (
        String,
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        bool,
        bool,
        String,
        String,
    ) = conn
        .query_row(
            "SELECT workspaceID, name, icon, colorHex, description, activeProviderID, isDisabled, isStarred, createdAt, updatedAt FROM service WHERE id = ?1",
            [id],
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
                ))
            },
        )
        .optional()
        .map_err(|e| map_db(&e.to_string()))?
        .ok_or_else(|| ServiceError::NotFound { id: id.into() })?;

    let group_ids = membership_ids(conn, id)?;
    let effective = effective_active_provider(conn, id)?;
    let providers = list_providers_brief(conn, id, effective.as_deref())?;
    let ports = visible_ports(conn, id, effective.as_deref())?;

    Ok(json!({
        "id": id,
        "workspaceID": workspace_id,
        "name": name,
        "icon": icon,
        "colorHex": color,
        "description": desc,
        "activeProviderID": effective,
        "isDisabled": disabled,
        "isStarred": starred,
        "groupIDs": group_ids,
        "providers": providers,
        "portMappings": ports,
        "createdAt": created,
        "updatedAt": updated,
    }))
}

pub fn list_item(
    conn: &Connection,
    service_id: &str,
    group_ids: &[String],
) -> Result<Value, ServiceError> {
    let (name, desc, disabled, starred, created): (String, Option<String>, bool, bool, String) =
        conn.query_row(
            "SELECT name, description, isDisabled, isStarred, createdAt FROM service WHERE id = ?1",
            [service_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .map_err(|e| map_db(&e.to_string()))?;
    let effective = effective_active_provider(conn, service_id)?;
    let (category, resolved, providers) = active_provider_card(conn, service_id, effective.as_deref())?;
    let local_ports = visible_local_ports(conn, service_id, effective.as_deref())?;
    let subtitle = {
        let d = desc.as_deref().unwrap_or("").trim();
        if !d.is_empty() {
            d.to_string()
        } else {
            resolved.clone()
        }
    };
    let display_subtitle = if !subtitle.is_empty() {
        subtitle.clone()
    } else {
        sidebar_label(&category).to_string()
    };
    Ok(json!({
        "id": service_id,
        "name": name,
        "groupIDs": group_ids,
        "isDisabled": disabled,
        "isStarred": starred,
        "activeProviderCategory": category,
        "resolvedTarget": resolved,
        "serviceDescription": desc,
        "localPorts": local_ports,
        "providerOptions": providers,
        "createdAt": created,
        "subtitle": subtitle,
        "displaySubtitle": display_subtitle,
        "runtime": json!({
            "status": if disabled { "disabled" } else { "stopped" },
            "isLoading": false,
            "statusTitle": if disabled { "Disabled" } else { "Stopped" },
        }),
    }))
}

fn list_providers_brief(
    conn: &Connection,
    sid: &str,
    active: Option<&str>,
) -> Result<Vec<Value>, ServiceError> {
    let mut stmt = conn
        .prepare(
            "SELECT id, type, label FROM provider WHERE serviceID = ?1 ORDER BY createdAt ASC, rowid ASC",
        )
        .map_err(|e| map_db(&e.to_string()))?;
    let rows = stmt
        .query_map([sid], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Option<String>>(2)?,
            ))
        })
        .map_err(|e| map_db(&e.to_string()))?;
    let mut out = Vec::new();
    for row in rows {
        let (id, ty, label) = row.map_err(|e| map_db(&e.to_string()))?;
        let raw = label.as_deref().unwrap_or("").trim().to_string();
        let display = if raw.is_empty() {
            sidebar_label(&ty).to_string()
        } else {
            raw.clone()
        };
        out.push(json!({
            "id": id,
            "category": ty,
            "label": raw,
            "isActive": active == Some(id.as_str()),
            "displayLabel": display,
        }));
    }
    Ok(out)
}

fn active_provider_card(
    conn: &Connection,
    sid: &str,
    active: Option<&str>,
) -> Result<(String, String, Vec<Value>), ServiceError> {
    let providers = list_providers_brief(conn, sid, active)?;
    let category = active
        .and_then(|id| {
            conn.query_row(
                "SELECT type, label FROM provider WHERE id = ?1",
                [id],
                |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)),
            )
            .ok()
        })
        .map(|(ty, label)| (ty.clone(), resolved_target(&ty, label.as_deref())))
        .unwrap_or_else(|| ("docker".into(), String::new()));
    Ok((category.0, category.1, providers))
}

fn membership_ids(conn: &Connection, sid: &str) -> Result<Vec<String>, ServiceError> {
    let mut stmt = conn
        .prepare(
            "SELECT groupID FROM service_group_membership WHERE serviceID = ?1 ORDER BY groupID ASC",
        )
        .map_err(|e| map_db(&e.to_string()))?;
    let rows = stmt
        .query_map([sid], |r| r.get(0))
        .map_err(|e| map_db(&e.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| map_db(&e.to_string()))
}

fn visible_ports(conn: &Connection, sid: &str, active: Option<&str>) -> Result<Vec<Value>, ServiceError> {
    let has_provider_rows: bool = conn
        .query_row(
            "SELECT 1 FROM portMapping WHERE serviceID = ?1 AND providerID IS NOT NULL LIMIT 1",
            [sid],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| map_db(&e.to_string()))?
        .is_some();
    let sql = if has_provider_rows {
        "SELECT id, serviceID, localPort, remotePort, protocolType, providerID FROM portMapping WHERE serviceID = ?1 AND providerID = ?2 ORDER BY rowid ASC"
    } else {
        "SELECT id, serviceID, localPort, remotePort, protocolType, providerID FROM portMapping WHERE serviceID = ?1 ORDER BY rowid ASC"
    };
    let maps = if has_provider_rows {
        let pid = active.unwrap_or("");
        let mut stmt = conn.prepare(sql).map_err(|e| map_db(&e.to_string()))?;
        let rows = stmt
            .query_map(rusqlite::params![sid, pid], port_row)
            .map_err(|e| map_db(&e.to_string()))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| map_db(&e.to_string()))?
    } else {
        let mut stmt = conn.prepare(sql).map_err(|e| map_db(&e.to_string()))?;
        let rows = stmt
            .query_map([sid], port_row)
            .map_err(|e| map_db(&e.to_string()))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| map_db(&e.to_string()))?
    };
    Ok(maps)
}

fn visible_local_ports(
    conn: &Connection,
    sid: &str,
    active: Option<&str>,
) -> Result<Vec<i64>, ServiceError> {
    let maps = visible_ports(conn, sid, active)?;
    Ok(maps
        .iter()
        .filter_map(|v| v.get("localPort").and_then(|p| p.as_i64()))
        .collect())
}

fn port_row(r: &Row<'_>) -> rusqlite::Result<Value> {
    Ok(json!({
        "id": r.get::<_, String>(0)?,
        "serviceID": r.get::<_, String>(1)?,
        "localPort": r.get::<_, i64>(2)?,
        "remotePort": r.get::<_, i64>(3)?,
        "protocolType": r.get::<_, String>(4)?,
        "providerID": r.get::<_, Option<String>>(5)?,
    }))
}

pub fn sidebar_label(type_: &str) -> &'static str {
    match type_ {
        "kubernetes" => "Kubernetes",
        "podman" => "Podman",
        "shell" => "Shell",
        "ssh" => "SSH",
        "httpCheck" => "Health Check",
        "tunnel" => "Tunnel",
        "processMonitor" => "Process Monitor",
        _ => "Docker",
    }
}

fn supports_auto_reconnect(type_: &str) -> bool {
    matches!(type_, "kubernetes" | "ssh" | "shell")
}

fn resolved_target(type_: &str, label: Option<&str>) -> String {
    let t = label.unwrap_or("").trim();
    if type_ == "kubernetes" && !t.is_empty() {
        format!("k8s: {t}")
    } else {
        t.to_string()
    }
}

fn map_db(detail: &str) -> ServiceError {
    ServiceError::InvalidPort {
        message: detail.into(),
    }
}
