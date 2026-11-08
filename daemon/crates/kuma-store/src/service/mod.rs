pub(crate) mod wire;

use crate::seed::{new_uppercase_uuid, now_grdb_datetime};
use kuma_domain::ServiceError;
use rusqlite::{Connection, OptionalExtension};
pub use wire::{effective_active_provider, provider_row_to_json, service_row, ProviderStoreHelper};
use serde_json::{json, Map, Value};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone)]
pub struct ServiceStore {
    conn: Arc<Mutex<Connection>>,
}

impl ServiceStore {
    pub fn new(conn: Arc<Mutex<Connection>>) -> Self {
        Self { conn }
    }

    pub fn list(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let ws = normalize_uuid(
            params
                .get("workspaceID")
                .and_then(|v| v.as_str())
                .unwrap_or(""),
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !workspace_exists(&conn, &ws)? {
            return Ok(json!({ "items": [], "totalCount": 0 }));
        }
        let total: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM service WHERE workspaceID = ?1",
                [&ws],
                |r| r.get(0),
            )
            .map_err(|e| map_db(&e.to_string()))?;
        if let Some(sort) = params.get("sort").and_then(|v| v.as_str()) {
            if !matches!(sort, "name" | "status" | "created") {
                return Err(ServiceError::InvalidPort {
                    message: format!("invalid sort: {sort}"),
                });
            }
        }
        let search = params
            .get("search")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_ascii_lowercase();
        let starred_only = params
            .get("starredOnly")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let sort = params.get("sort").and_then(|v| v.as_str());
        let group_filter = params
            .get("groupID")
            .and_then(|v| v.as_str())
            .map(normalize_uuid)
            .transpose()?;
        let status_filter: Vec<String> = params
            .get("statuses")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(str::to_ascii_lowercase))
                    .collect()
            })
            .unwrap_or_default();
        let provider_filter: Vec<String> = params
            .get("providers")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str().map(str::to_ascii_lowercase))
                    .collect()
            })
            .unwrap_or_default();
        let live_target = params
            .get("liveTarget")
            .and_then(|v| v.as_str())
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty());
        let mut stmt = conn
            .prepare(
                "SELECT id FROM service WHERE workspaceID = ?1 ORDER BY createdAt ASC, rowid ASC",
            )
            .map_err(|e| map_db(&e.to_string()))?;
        let ids: Vec<String> = stmt
            .query_map([&ws], |r| r.get(0))
            .map_err(|e| map_db(&e.to_string()))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| map_db(&e.to_string()))?;
        let mut items = Vec::new();
        for sid in ids {
            let groups = membership_ids(&conn, &sid)?;
            if starred_only {
                let starred: bool = conn
                    .query_row(
                        "SELECT isStarred FROM service WHERE id = ?1",
                        [&sid],
                        |r| r.get(0),
                    )
                    .map_err(|e| map_db(&e.to_string()))?;
                if !starred {
                    continue;
                }
            }
            if let Some(ref gid) = group_filter {
                if !groups.contains(gid) {
                    continue;
                }
            }
            let item = wire::list_item(&conn, &sid, &groups)?;
            if !search.is_empty() {
                let name = item
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                let subtitle = item
                    .get("subtitle")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if !name.contains(&search) && !subtitle.contains(&search) {
                    continue;
                }
            }
            if !status_filter.is_empty() {
                let st = item
                    .get("runtime")
                    .and_then(|r| r.get("status"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("stopped")
                    .to_ascii_lowercase();
                if !status_filter.iter().any(|f| f == &st) {
                    continue;
                }
            }
            if !provider_filter.is_empty() {
                let cat = item
                    .get("activeProviderCategory")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if !provider_filter.iter().any(|f| f == &cat) {
                    continue;
                }
            }
            if let Some(ref needle) = live_target {
                let target = item
                    .get("resolvedTarget")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if !target.contains(needle) {
                    continue;
                }
            }
            items.push(item);
        }
        if sort == Some("name") {
            items.sort_by(|a, b| {
                a.get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase()
                    .cmp(
                        &b.get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_ascii_lowercase(),
                    )
            });
        } else if sort == Some("created") {
            items.sort_by(|a, b| {
                b.get("createdAt")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .cmp(a.get("createdAt").and_then(|v| v.as_str()).unwrap_or(""))
            });
        }
        Ok(json!({ "items": items, "totalCount": total }))
    }

    pub fn get(&self, id: &str) -> Result<Value, ServiceError> {
        let id = normalize_uuid(id)?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        service_row(&conn, &id)
    }

    pub fn create(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let ws = normalize_uuid(
            params
                .get("workspaceID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::WorkspaceNotFound { id: "".into() })?,
        )?;
        let name = params
            .get("name")
            .and_then(|v| v.as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .ok_or(ServiceError::NameEmpty)?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !workspace_exists(&conn, &ws)? {
            return Err(ServiceError::WorkspaceNotFound { id: ws });
        }
        let desc = params.get("description").and_then(|v| v.as_str());
        let disabled = params
            .get("isDisabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let starred = params
            .get("isStarred")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let sid = new_uppercase_uuid();
        let pid = new_uppercase_uuid();
        let now = now_grdb_datetime();
        let ptype = params
            .get("provider")
            .and_then(|v| v.get("type"))
            .and_then(|v| v.as_str())
            .unwrap_or("docker");
        let plabel = params
            .get("provider")
            .and_then(|v| v.get("label"))
            .and_then(|v| v.as_str());
        let tx = conn.unchecked_transaction().map_err(|e| map_db(&e.to_string()))?;
        tx.execute(
            "INSERT INTO service (id, workspaceID, name, description, isDisabled, isStarred, createdAt, updatedAt) VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
            rusqlite::params![sid, ws, name, desc, disabled, starred, now, now],
        )
        .map_err(|e| map_db(&e.to_string()))?;
        tx.execute(
            "INSERT INTO provider (id, serviceID, type, label, kubeConfigID, createdAt, updatedAt, autoReconnect) VALUES (?1,?2,?3,?4,CASE WHEN ?3 = 'kubernetes' THEN ?7 ELSE NULL END,?5,?6,0)",
            rusqlite::params![pid, sid, ptype, plabel, now, now, crate::kubeconfig::DEFAULT_ID],
        )
        .map_err(|e| map_db(&e.to_string()))?;
        tx.execute(
            "UPDATE service SET activeProviderID = ?1 WHERE id = ?2",
            rusqlite::params![pid, sid],
        )
        .map_err(|e| map_db(&e.to_string()))?;
        if let Some(groups) = params.get("groupIDs").and_then(|v| v.as_array()) {
            for g in groups {
                let Some(gs) = g.as_str() else { continue };
                let gid = normalize_uuid(gs)?;
                ensure_group_in_workspace(&tx, &gid, &ws)?;
                tx.execute(
                    "INSERT INTO service_group_membership (serviceID, groupID, createdAt) VALUES (?1,?2,?3)",
                    rusqlite::params![sid, gid, now],
                )
                .map_err(|e| map_db(&e.to_string()))?;
            }
        }
        if let Some(ports) = params.get("ports").and_then(|v| v.as_array()) {
            for (i, row) in ports.iter().enumerate() {
                let local = row.get("localPort").and_then(|v| v.as_i64());
                let remote = row.get("remotePort").and_then(|v| v.as_i64());
                if !port_valid(local) || !port_valid(remote) {
                    return Err(ServiceError::InvalidPort {
                        message: format!(
                            "Port row {}: enter local and remote ports (1\u{2013}65535).",
                            i + 1
                        ),
                    });
                }
                let map_id = new_uppercase_uuid();
                tx.execute(
                    "INSERT INTO portMapping (id, serviceID, localPort, remotePort, protocolType, providerID) VALUES (?1,?2,?3,?4,'TCP',?5)",
                    rusqlite::params![map_id, sid, local.unwrap(), remote.unwrap(), pid],
                )
                .map_err(|e| map_db(&e.to_string()))?;
            }
        }
        tx.commit().map_err(|e| map_db(&e.to_string()))?;
        service_row(&conn, &sid)
    }

    pub fn update(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        for key in ["id", "workspaceID", "createdAt", "activeProviderID"] {
            if params.get(key).is_some() {
                return Err(ServiceError::FieldReadonly {
                    field: key.into(),
                });
            }
        }
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &id)? {
            return Err(ServiceError::NotFound { id });
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_stale(&conn, &id, exp)?;
        }
        let now = now_grdb_datetime();
        if let Some(name) = params.get("name") {
            let Some(s) = name.as_str() else {
                return Err(ServiceError::NameEmpty);
            };
            if s.trim().is_empty() {
                return Err(ServiceError::NameEmpty);
            }
            conn.execute(
                "UPDATE service SET name = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![s.trim(), now, id],
            )
            .map_err(|e| map_db(&e.to_string()))?;
        }
        if let Some(desc) = params.get("description") {
            let s = desc.as_str();
            conn.execute(
                "UPDATE service SET description = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![s, now, id],
            )
            .map_err(|e| map_db(&e.to_string()))?;
        }
        if let Some(groups) = params.get("groupIDs").and_then(|v| v.as_array()) {
            let ws: String = conn
                .query_row(
                    "SELECT workspaceID FROM service WHERE id = ?1",
                    [&id],
                    |r| r.get(0),
                )
                .map_err(|e| map_db(&e.to_string()))?;
            conn.execute(
                "DELETE FROM service_group_membership WHERE serviceID = ?1",
                [&id],
            )
            .map_err(|e| map_db(&e.to_string()))?;
            for g in groups {
                let Some(gs) = g.as_str() else { continue };
                let gid = normalize_uuid(gs)?;
                ensure_group_in_workspace(&conn, &gid, &ws)?;
                conn.execute(
                    "INSERT INTO service_group_membership (serviceID, groupID, createdAt) VALUES (?1,?2,?3)",
                    rusqlite::params![id, gid, now],
                )
                .map_err(|e| map_db(&e.to_string()))?;
            }
            conn.execute(
                "UPDATE service SET updatedAt = ?1 WHERE id = ?2",
                rusqlite::params![now, id],
            )
            .map_err(|e| map_db(&e.to_string()))?;
        }
        service_row(&conn, &id)
    }

    pub fn delete(&self, id: &str) -> Result<Value, ServiceError> {
        let id = normalize_uuid(id)?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &id)? {
            return Err(ServiceError::NotFound { id });
        }
        conn.execute("DELETE FROM service WHERE id = ?1", [&id])
            .map_err(|e| map_db(&e.to_string()))?;
        Ok(json!({ "deleted": true }))
    }

    pub fn duplicate(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let src = self.get(&id)?;
        let ws = src
            .get("workspaceID")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let mut create = Map::new();
        create.insert(
            "workspaceID".into(),
            Value::String(ws.to_string()),
        );
        create.insert(
            "name".into(),
            json!(format!(
                "{} Copy",
                src.get("name").and_then(|v| v.as_str()).unwrap_or("Service")
            )),
        );
        if let Some(d) = src.get("description") {
            create.insert("description".into(), d.clone());
        }
        create.insert("groupIDs".into(), src.get("groupIDs").cloned().unwrap_or(json!([])));
        self.create(&create)
    }

    pub fn set_starred(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &id)? {
            return Err(ServiceError::NotFound { id });
        }
        let val = match params.get("starred").and_then(|v| v.as_bool()) {
            Some(b) => b,
            None => {
                let cur: bool = conn
                    .query_row(
                        "SELECT isStarred FROM service WHERE id = ?1",
                        [&id],
                        |r| r.get(0),
                    )
                    .map_err(|e| map_db(&e.to_string()))?;
                !cur
            }
        };
        drop(conn);
        self.set_flag(&id, "isStarred", val, params)
    }

    pub fn set_disabled(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let disabled = params
            .get("disabled")
            .and_then(|v| v.as_bool())
            .ok_or_else(|| ServiceError::InvalidPort {
                message: "missing disabled".into(),
            })?;
        self.set_flag(&id, "isDisabled", disabled, params)
    }

    fn set_flag(
        &self,
        id: &str,
        column: &str,
        value: bool,
        params: &Map<String, Value>,
    ) -> Result<Value, ServiceError> {
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, id)? {
            return Err(ServiceError::NotFound { id: id.into() });
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_stale(&conn, id, exp)?;
        }
        let now = now_grdb_datetime();
        let sql = format!("UPDATE service SET {column} = ?1, updatedAt = ?2 WHERE id = ?3");
        conn.execute(&sql, rusqlite::params![value, now, id])
            .map_err(|e| map_db(&e.to_string()))?;
        service_row(&conn, id)
    }

    pub fn set_groups(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let mut patch = Map::new();
        patch.insert("id".into(), json!(id));
        if let Some(g) = params.get("groupIDs") {
            patch.insert("groupIDs".into(), g.clone());
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            patch.insert("expectedUpdatedAt".into(), exp.clone());
        }
        self.update(&patch)
    }

    pub fn toggle_group(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let gid = normalize_uuid(
            params
                .get("groupID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::GroupNotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &id)? {
            return Err(ServiceError::NotFound { id });
        }
        let ws: String = conn
            .query_row(
                "SELECT workspaceID FROM service WHERE id = ?1",
                [&id],
                |r| r.get(0),
            )
            .map_err(|e| map_db(&e.to_string()))?;
        ensure_group_in_workspace(&conn, &gid, &ws)?;
        let now = now_grdb_datetime();
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM service_group_membership WHERE serviceID = ?1 AND groupID = ?2",
                rusqlite::params![id, gid],
                |_| Ok(()),
            )
            .optional()
            .map_err(|e| map_db(&e.to_string()))?
            .is_some();
        if exists {
            conn.execute(
                "DELETE FROM service_group_membership WHERE serviceID = ?1 AND groupID = ?2",
                rusqlite::params![id, gid],
            )
            .map_err(|e| map_db(&e.to_string()))?;
        } else {
            conn.execute(
                "INSERT INTO service_group_membership (serviceID, groupID, createdAt) VALUES (?1,?2,?3)",
                rusqlite::params![id, gid, now],
            )
            .map_err(|e| map_db(&e.to_string()))?;
        }
        conn.execute(
            "UPDATE service SET updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now, id],
        )
        .map_err(|e| map_db(&e.to_string()))?;
        service_row(&conn, &id)
    }

    pub fn switch_provider(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
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
        if !service_exists(&conn, &id)? {
            return Err(ServiceError::NotFound { id });
        }
        let prov_sid: String = conn
            .query_row(
                "SELECT serviceID FROM provider WHERE id = ?1",
                [&pid],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| map_db(&e.to_string()))?
            .ok_or_else(|| ServiceError::ProviderNotFound { id: pid.clone() })?;
        if prov_sid != id {
            return Err(ServiceError::ProviderNotFound { id: pid });
        }
        let active = wire::effective_active_provider(&conn, &id)?;
        if active.as_deref() == Some(pid.as_str()) {
            return Ok(json!({
                "service": service_row(&conn, &id)?,
                "changed": false,
                "restart": { "attempted": false, "started": false },
            }));
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_stale(&conn, &id, exp)?;
        }
        let now = now_grdb_datetime();
        conn.execute(
            "UPDATE service SET activeProviderID = ?1, updatedAt = ?2 WHERE id = ?3",
            rusqlite::params![pid, now, id],
        )
        .map_err(|e| map_db(&e.to_string()))?;
        Ok(json!({
            "service": service_row(&conn, &id)?,
            "changed": true,
            "restart": { "attempted": false, "started": false },
        }))
    }

    pub fn preflight(&self, params: &Map<String, Value>) -> Result<Value, ServiceError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| ServiceError::NotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| lock_err())?;
        if !service_exists(&conn, &id)? {
            return Err(ServiceError::NotFound { id });
        }
        crate::validation::service_preflight(&conn, &id)
    }
}

fn port_valid(p: Option<i64>) -> bool {
    p.map(|n| (1..=65535).contains(&n)).unwrap_or(false)
}

fn normalize_uuid(id: &str) -> Result<String, ServiceError> {
    Uuid::parse_str(id.trim())
        .map(|u| u.to_string().to_uppercase())
        .map_err(|_| ServiceError::NotFound { id: id.into() })
}

fn workspace_exists(conn: &Connection, id: &str) -> Result<bool, ServiceError> {
    Ok(conn
        .query_row("SELECT 1 FROM workspace WHERE id = ?1", [id], |_| Ok(()))
        .optional()
        .map_err(|e| map_db(&e.to_string()))?
        .is_some())
}

fn service_exists(conn: &Connection, id: &str) -> Result<bool, ServiceError> {
    Ok(conn
        .query_row("SELECT 1 FROM service WHERE id = ?1", [id], |_| Ok(()))
        .optional()
        .map_err(|e| map_db(&e.to_string()))?
        .is_some())
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

fn ensure_group_in_workspace(
    conn: &Connection,
    gid: &str,
    ws: &str,
) -> Result<(), ServiceError> {
    let row: Option<String> = conn
        .query_row(
            "SELECT workspaceID FROM service_group WHERE id = ?1",
            [gid],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| map_db(&e.to_string()))?;
    let Some(gws) = row else {
        return Err(ServiceError::GroupNotFound { id: gid.into() });
    };
    if gws != ws {
        return Err(ServiceError::GroupWorkspaceMismatch);
    }
    Ok(())
}

fn check_stale(conn: &Connection, id: &str, expected: &Value) -> Result<(), ServiceError> {
    let current: String = conn
        .query_row(
            "SELECT updatedAt FROM service WHERE id = ?1",
            [id],
            |r| r.get(0),
        )
        .map_err(|e| map_db(&e.to_string()))?;
    match expected {
        Value::String(s) if s == &current => Ok(()),
        _ => Err(ServiceError::ConflictStale),
    }
}

fn lock_err() -> ServiceError {
    ServiceError::InvalidPort {
        message: "lock poisoned".into(),
    }
}

fn map_db(detail: &str) -> ServiceError {
    ServiceError::InvalidPort {
        message: detail.into(),
    }
}
