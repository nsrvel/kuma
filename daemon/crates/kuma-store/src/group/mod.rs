use crate::seed::{new_uppercase_uuid, now_grdb_datetime};
use kuma_domain::GroupError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Map, Value};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone)]
pub struct GroupStore {
    conn: Arc<Mutex<Connection>>,
}

impl GroupStore {
    pub fn new(conn: Arc<Mutex<Connection>>) -> Self {
        Self { conn }
    }

    pub fn list(&self, workspace_id: &str) -> Result<Vec<Value>, GroupError> {
        let ws = normalize_uuid(workspace_id)?;
        if !workspace_exists(&self.conn, &ws)? {
            return Err(GroupError::WorkspaceNotFound { id: ws });
        }
        query_groups(&self.conn, &ws)
    }

    pub fn create(&self, params: &Map<String, Value>) -> Result<Value, GroupError> {
        let ws = normalize_uuid(
            params
                .get("workspaceID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| GroupError::WorkspaceNotFound { id: "".into() })?,
        )?;
        if !workspace_exists(&self.conn, &ws)? {
            return Err(GroupError::WorkspaceNotFound { id: ws });
        }
        let name = name_from_create(params.get("name"));
        let id = new_uppercase_uuid();
        let now = now_grdb_datetime();
        let conn = self.conn.lock().map_err(|_| db_err("lock"))?;
        let max: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(sortOrder), 0) FROM service_group WHERE workspaceID = ?1",
                [&ws],
                |r| r.get(0),
            )
            .map_err(|e| db_err(&e.to_string()))?;
        conn.execute(
            "INSERT INTO service_group (id, workspaceID, name, sortOrder, createdAt, updatedAt) VALUES (?1,?2,?3,?4,?5,?6)",
            rusqlite::params![id, ws, name, max + 1, now, now],
        )
        .map_err(|e| db_err(&e.to_string()))?;
        row_to_group(&conn, &id)
    }

    pub fn update(&self, params: &Map<String, Value>) -> Result<Value, GroupError> {
        let id = normalize_uuid(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| GroupError::NotFound { id: "".into() })?,
        )?;
        let conn = self.conn.lock().map_err(|_| db_err("lock"))?;
        if !group_exists(&conn, &id)? {
            return Err(GroupError::NotFound { id });
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_stale(&conn, &id, exp)?;
        }
        if let Some(name) = params.get("name") {
            let Some(s) = name.as_str() else {
                return Err(GroupError::ReorderInvalid {
                    message: "invalid name".into(),
                });
            };
            let trimmed = s.trim();
            let final_name = if trimmed.is_empty() {
                "Untitled Group".into()
            } else {
                trimmed.to_string()
            };
            let now = now_grdb_datetime();
            conn.execute(
                "UPDATE service_group SET name = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![final_name, now, id],
            )
            .map_err(|e| db_err(&e.to_string()))?;
        }
        row_to_group(&conn, &id)
    }

    pub fn delete(&self, id: &str) -> Result<Value, GroupError> {
        let id = normalize_uuid(id)?;
        let conn = self.conn.lock().map_err(|_| db_err("lock"))?;
        if !group_exists(&conn, &id)? {
            return Err(GroupError::NotFound { id });
        }
        conn.execute("DELETE FROM service_group WHERE id = ?1", [&id])
            .map_err(|e| db_err(&e.to_string()))?;
        Ok(json!({ "deleted": true }))
    }

    pub fn reorder(&self, params: &Map<String, Value>) -> Result<Vec<Value>, GroupError> {
        let ws = normalize_uuid(
            params
                .get("workspaceID")
                .and_then(|v| v.as_str())
                .ok_or_else(|| GroupError::WorkspaceNotFound { id: "".into() })?,
        )?;
        if !workspace_exists(&self.conn, &ws)? {
            return Err(GroupError::WorkspaceNotFound { id: ws.clone() });
        }
        let conn = self.conn.lock().map_err(|_| db_err("lock"))?;
        let now = now_grdb_datetime();
        let has_perm = params.get("groupIDs").is_some();
        let has_swap = params.get("fromIndex").is_some() || params.get("toIndex").is_some();
        if has_perm == has_swap {
            return Err(GroupError::ReorderInvalid {
                message: "Specify either groupIDs or fromIndex and toIndex".into(),
            });
        }
        if let Some(ids) = params.get("groupIDs").and_then(|v| v.as_array()) {
            let all = group_ids_in_workspace(&conn, &ws)?;
            if ids.len() != all.len() {
                return Err(GroupError::ReorderInvalid {
                    message: "groupIDs must list every group exactly once".into(),
                });
            }
            let mut seen = std::collections::HashSet::new();
            for (i, item) in ids.iter().enumerate() {
                let Some(s) = item.as_str() else {
                    return Err(GroupError::ReorderInvalid {
                        message: "invalid group id".into(),
                    });
                };
                let gid = normalize_uuid(s)?;
                if !all.contains(&gid) || !seen.insert(gid.clone()) {
                    return Err(GroupError::ReorderInvalid {
                        message: "groupIDs must list every group exactly once".into(),
                    });
                }
                conn.execute(
                    "UPDATE service_group SET sortOrder = ?1, updatedAt = ?2 WHERE id = ?3",
                    rusqlite::params![i as i64, now, gid],
                )
                .map_err(|e| db_err(&e.to_string()))?;
            }
        } else {
            let from = params
                .get("fromIndex")
                .and_then(|v| v.as_i64())
                .unwrap_or(-1);
            let to = params.get("toIndex").and_then(|v| v.as_i64()).unwrap_or(-1);
            let mut ids = group_ids_in_workspace(&conn, &ws)?;
            if from == to
                || from < 0
                || to < 0
                || from >= ids.len() as i64
                || to >= ids.len() as i64
            {
                return query_groups(&self.conn, &ws);
            }
            let item = ids.remove(from as usize);
            ids.insert(to as usize, item);
            for (i, gid) in ids.iter().enumerate() {
                conn.execute(
                    "UPDATE service_group SET sortOrder = ?1, updatedAt = ?2 WHERE id = ?3",
                    rusqlite::params![i as i64, now, gid],
                )
                .map_err(|e| db_err(&e.to_string()))?;
            }
        }
        drop(conn);
        self.list(&ws)
    }
}

fn query_groups(conn: &Arc<Mutex<Connection>>, ws: &str) -> Result<Vec<Value>, GroupError> {
    let conn = conn.lock().map_err(|_| db_err("lock"))?;
    let mut stmt = conn
        .prepare(
            "SELECT id, workspaceID, name, sortOrder, createdAt, updatedAt FROM service_group WHERE workspaceID = ?1 ORDER BY sortOrder ASC, createdAt ASC, rowid ASC",
        )
        .map_err(|e| db_err(&e.to_string()))?;
    let rows = stmt
        .query_map([ws], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, i64>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
            ))
        })
        .map_err(|e| db_err(&e.to_string()))?;
    let mut out = Vec::new();
    for row in rows {
        let (id, workspace_id, name, sort, created, updated) =
            row.map_err(|e| db_err(&e.to_string()))?;
        out.push(json!({
            "id": id,
            "workspaceID": workspace_id,
            "name": name,
            "sortOrder": sort,
            "createdAt": created,
            "updatedAt": updated,
        }));
    }
    Ok(out)
}

fn row_to_group(conn: &Connection, id: &str) -> Result<Value, GroupError> {
    conn.query_row(
        "SELECT id, workspaceID, name, sortOrder, createdAt, updatedAt FROM service_group WHERE id = ?1",
        [id],
        |r| {
            Ok(json!({
                "id": r.get::<_, String>(0)?,
                "workspaceID": r.get::<_, String>(1)?,
                "name": r.get::<_, String>(2)?,
                "sortOrder": r.get::<_, i64>(3)?,
                "createdAt": r.get::<_, String>(4)?,
                "updatedAt": r.get::<_, String>(5)?,
            }))
        },
    )
    .map_err(|_| GroupError::NotFound { id: id.into() })
}

fn normalize_uuid(id: &str) -> Result<String, GroupError> {
    Uuid::parse_str(id.trim())
        .map(|u| u.to_string().to_uppercase())
        .map_err(|_| GroupError::NotFound { id: id.into() })
}

fn name_from_create(name: Option<&Value>) -> String {
    match name.and_then(|v| v.as_str()) {
        None => "New Group".into(),
        Some(s) if s.trim().is_empty() => "New Group".into(),
        Some(s) => s.trim().to_string(),
    }
}

fn workspace_exists(conn: &Arc<Mutex<Connection>>, id: &str) -> Result<bool, GroupError> {
    let conn = conn.lock().map_err(|_| db_err("lock"))?;
    Ok(conn
        .query_row("SELECT 1 FROM workspace WHERE id = ?1", [id], |_| Ok(()))
        .optional()
        .map_err(|e| db_err(&e.to_string()))?
        .is_some())
}

fn group_exists(conn: &Connection, id: &str) -> Result<bool, GroupError> {
    Ok(conn
        .query_row(
            "SELECT 1 FROM service_group WHERE id = ?1",
            [id],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| db_err(&e.to_string()))?
        .is_some())
}

fn group_ids_in_workspace(conn: &Connection, ws: &str) -> Result<Vec<String>, GroupError> {
    let mut stmt = conn
        .prepare(
            "SELECT id FROM service_group WHERE workspaceID = ?1 ORDER BY sortOrder ASC, createdAt ASC, rowid ASC",
        )
        .map_err(|e| db_err(&e.to_string()))?;
    let rows = stmt
        .query_map([ws], |r| r.get(0))
        .map_err(|e| db_err(&e.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| db_err(&e.to_string()))
}

fn check_stale(conn: &Connection, id: &str, expected: &Value) -> Result<(), GroupError> {
    let current: String = conn
        .query_row(
            "SELECT updatedAt FROM service_group WHERE id = ?1",
            [id],
            |r| r.get(0),
        )
        .map_err(|e| db_err(&e.to_string()))?;
    match expected {
        Value::String(s) if s == &current => Ok(()),
        _ => Err(GroupError::ConflictStale),
    }
}

fn db_err(detail: &str) -> GroupError {
    GroupError::ReorderInvalid {
        message: detail.into(),
    }
}
