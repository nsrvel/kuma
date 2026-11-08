mod image;

use crate::seed::{new_uppercase_uuid, now_grdb_datetime};
use kuma_domain::WorkspaceError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Map, Value};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Clone)]
pub struct WorkspaceStore {
    conn: Arc<Mutex<Connection>>,
    data_dir: PathBuf,
}

impl WorkspaceStore {
    pub fn new(conn: Arc<Mutex<Connection>>, data_dir: PathBuf) -> Self {
        Self { conn, data_dir }
    }

    pub fn list(&self) -> Result<Vec<Value>, WorkspaceError> {
        let conn = self.conn.lock().map_err(|_| WorkspaceError::ImageIo {
            detail: "lock".into(),
        })?;
        let mut stmt = conn
            .prepare(
                "SELECT id, name, imagePath, sortOrder, createdAt, updatedAt FROM workspace ORDER BY sortOrder ASC, createdAt ASC, rowid ASC",
            )
            .map_err(|e| db_err(&e))?;
        let rows = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, Option<String>>(2)?,
                    r.get::<_, i64>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, String>(5)?,
                ))
            })
            .map_err(|e| db_err(&e))?;
        let mut out = Vec::new();
        for row in rows {
            let (id, name, image, sort, created, updated) =
                row.map_err(|e| db_err(&e))?;
            out.push(wire_workspace(&self.data_dir, &id, &name, image, sort, &created, &updated));
        }
        Ok(out)
    }

    pub fn get(&self, id: &str) -> Result<Value, WorkspaceError> {
        let id = normalize_id(id)?;
        let conn = self.conn.lock().map_err(|_| WorkspaceError::ImageIo {
            detail: "lock".into(),
        })?;
        row_to_wire(&conn, &self.data_dir, &id)
    }

    pub fn create(&self, params: &Map<String, Value>) -> Result<Value, WorkspaceError> {
        let name = name_from_create(params.get("name"));
        let id = new_uppercase_uuid();
        let now = now_grdb_datetime();
        let conn = self.conn.lock().map_err(|_| WorkspaceError::ImageIo {
            detail: "lock".into(),
        })?;
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM workspace", [], |r| r.get(0))
            .map_err(|e| db_err(&e))?;
        let mut image_path: Option<String> = None;
        if let Some(b64) = params.get("imageBase64").and_then(|v| v.as_str()) {
            image_path = Some(store_image(&self.data_dir, &id, b64)?);
        }
        conn.execute(
            "INSERT INTO workspace (id, name, imagePath, sortOrder, createdAt, updatedAt) VALUES (?1,?2,?3,?4,?5,?6)",
            rusqlite::params![id, name, image_path, count, now, now],
        )
        .map_err(|e| db_err(&e))?;
        row_to_wire(&conn, &self.data_dir, &id)
    }

    pub fn update(&self, params: &Map<String, Value>) -> Result<Value, WorkspaceError> {
        let id = normalize_id(params.get("id").and_then(|v| v.as_str()).ok_or_else(|| WorkspaceError::NotFound { id: "".into() })?)?;
        if params.get("imageBase64").is_some() && params.get("clearImage").and_then(|v| v.as_bool()) == Some(true) {
            return Err(WorkspaceError::ImageConflict);
        }
        let conn = self.conn.lock().map_err(|_| WorkspaceError::ImageIo {
            detail: "lock".into(),
        })?;
        if !workspace_exists(&conn, &id)? {
            return Err(WorkspaceError::NotFound { id });
        }
        if let Some(exp) = params.get("expectedUpdatedAt") {
            check_stale(&conn, &id, exp)?;
        }
        let mut now = now_grdb_datetime();
        if let Some(name) = params.get("name") {
            let Some(s) = name.as_str() else {
                return Err(WorkspaceError::NameEmpty);
            };
            let trimmed = s.trim();
            if trimmed.is_empty() {
                return Err(WorkspaceError::NameEmpty);
            }
            conn.execute(
                "UPDATE workspace SET name = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![trimmed, now, id],
            )
            .map_err(|e| db_err(&e))?;
        }
        if params.get("clearImage").and_then(|v| v.as_bool()) == Some(true) {
            clear_managed_image(&conn, &self.data_dir, &id)?;
            now = now_grdb_datetime();
        }
        if let Some(b64) = params.get("imageBase64").and_then(|v| v.as_str()) {
            let path = store_image(&self.data_dir, &id, b64)?;
            conn.execute(
                "UPDATE workspace SET imagePath = ?1, updatedAt = ?2 WHERE id = ?3",
                rusqlite::params![path, now, id],
            )
            .map_err(|e| db_err(&e))?;
        }
        row_to_wire(&conn, &self.data_dir, &id)
    }

    pub fn delete(&self, id: &str) -> Result<Value, WorkspaceError> {
        let id = normalize_id(id)?;
        let conn = self.conn.lock().map_err(|_| WorkspaceError::ImageIo {
            detail: "lock".into(),
        })?;
        let count: i64 = conn
            .query_row("SELECT COUNT(*) FROM workspace", [], |r| r.get(0))
            .map_err(|e| db_err(&e))?;
        if count <= 1 {
            return Err(WorkspaceError::LastWorkspace { id });
        }
        if !workspace_exists(&conn, &id)? {
            return Err(WorkspaceError::NotFound { id: id.clone() });
        }
        clear_managed_image(&conn, &self.data_dir, &id)?;
        conn.execute("DELETE FROM workspace WHERE id = ?1", [&id])
            .map_err(|e| db_err(&e))?;
        let next: Option<String> = conn
            .query_row(
                "SELECT id FROM workspace ORDER BY sortOrder ASC, createdAt ASC, rowid ASC LIMIT 1",
                [],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| db_err(&e))?;
        Ok(json!({ "deleted": true, "nextWorkspaceId": next }))
    }

    pub fn set_image(&self, params: &Map<String, Value>) -> Result<Value, WorkspaceError> {
        let id = normalize_id(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| WorkspaceError::NotFound { id: "".into() })?,
        )?;
        let b64 = params
            .get("imageBase64")
            .and_then(|v| v.as_str())
            .ok_or(WorkspaceError::ImageInvalid)?;
        let mut patch = Map::new();
        patch.insert("id".into(), json!(id));
        patch.insert("imageBase64".into(), json!(b64));
        if let Some(exp) = params.get("expectedUpdatedAt") {
            patch.insert("expectedUpdatedAt".into(), exp.clone());
        }
        self.update(&patch)
    }

    pub fn clear_image(&self, params: &Map<String, Value>) -> Result<Value, WorkspaceError> {
        let id = normalize_id(
            params
                .get("id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| WorkspaceError::NotFound { id: "".into() })?,
        )?;
        let mut patch = Map::new();
        patch.insert("id".into(), json!(id));
        patch.insert("clearImage".into(), json!(true));
        if let Some(exp) = params.get("expectedUpdatedAt") {
            patch.insert("expectedUpdatedAt".into(), exp.clone());
        }
        self.update(&patch)
    }

    pub fn get_image(&self, id: &str) -> Result<Value, WorkspaceError> {
        use base64::Engine;
        let id = normalize_id(id)?;
        let ws = self.get(&id)?;
        let image_path = ws.get("imagePath").and_then(|v| v.as_str());
        let has = ws.get("hasImage").and_then(|v| v.as_bool()).unwrap_or(false);
        if !has {
            return Ok(json!({ "hasImage": false }));
        }
        let path = match image_path {
            Some(p) if p.starts_with('/') => std::path::PathBuf::from(p),
            Some(p) => images_dir(&self.data_dir).join(p),
            None => return Ok(json!({ "hasImage": false })),
        };
        let bytes = std::fs::read(&path).map_err(|e| WorkspaceError::ImageIo {
            detail: e.to_string(),
        })?;
        let b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
        Ok(json!({ "hasImage": true, "imageBase64": b64 }))
    }

    pub fn reorder(&self, params: &Map<String, Value>) -> Result<Vec<Value>, WorkspaceError> {
        let has_perm = params.get("workspaceIDs").is_some();
        let has_swap = params.get("fromIndex").is_some() || params.get("toIndex").is_some();
        if has_perm == has_swap {
            return Err(WorkspaceError::ReorderInvalid {
                message: "Specify either workspaceIDs or fromIndex and toIndex".into(),
            });
        }
        let conn = self.conn.lock().map_err(|_| WorkspaceError::ImageIo {
            detail: "lock".into(),
        })?;
        let now = now_grdb_datetime();
        if let Some(ids) = params.get("workspaceIDs").and_then(|v| v.as_array()) {
            let all: Vec<String> = conn
                .prepare("SELECT id FROM workspace ORDER BY sortOrder ASC, createdAt ASC, rowid ASC")
                .map_err(|e| db_err(&e))?
                .query_map([], |r| r.get(0))
                .map_err(|e| db_err(&e))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| db_err(&e))?;
            if ids.len() != all.len() {
                return Err(WorkspaceError::ReorderInvalid {
                    message: "workspaceIDs must list every workspace exactly once".into(),
                });
            }
            let mut seen = std::collections::HashSet::new();
            for (i, item) in ids.iter().enumerate() {
                let Some(s) = item.as_str() else {
                    return Err(WorkspaceError::ReorderInvalid {
                        message: "workspaceIDs must list every workspace exactly once".into(),
                    });
                };
                let id = normalize_id(s)?;
                if !all.contains(&id) || !seen.insert(id.clone()) {
                    return Err(WorkspaceError::ReorderInvalid {
                        message: "workspaceIDs must list every workspace exactly once".into(),
                    });
                }
                conn.execute(
                    "UPDATE workspace SET sortOrder = ?1, updatedAt = ?2 WHERE id = ?3",
                    rusqlite::params![i as i64, now, id],
                )
                .map_err(|e| db_err(&e))?;
            }
        } else {
            let from = params.get("fromIndex").and_then(|v| v.as_i64()).unwrap_or(-1);
            let to = params.get("toIndex").and_then(|v| v.as_i64()).unwrap_or(-1);
            let mut ids: Vec<String> = conn
                .prepare("SELECT id FROM workspace ORDER BY sortOrder ASC, createdAt ASC, rowid ASC")
                .map_err(|e| db_err(&e))?
                .query_map([], |r| r.get(0))
                .map_err(|e| db_err(&e))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| db_err(&e))?;
            if from == to || from < 0 || to < 0 || from >= ids.len() as i64 || to >= ids.len() as i64 {
                return self.list();
            }
            let item = ids.remove(from as usize);
            ids.insert(to as usize, item);
            for (i, id) in ids.iter().enumerate() {
                conn.execute(
                    "UPDATE workspace SET sortOrder = ?1, updatedAt = ?2 WHERE id = ?3",
                    rusqlite::params![i as i64, now, id],
                )
                .map_err(|e| db_err(&e))?;
            }
        }
        drop(conn);
        self.list()
    }
}

fn normalize_id(id: &str) -> Result<String, WorkspaceError> {
    Uuid::parse_str(id.trim())
        .map(|u| u.to_string().to_uppercase())
        .map_err(|_| WorkspaceError::NotFound {
            id: id.to_string(),
        })
}

fn name_from_create(name: Option<&Value>) -> String {
    match name.and_then(|v| v.as_str()) {
        None => "New Workspace".into(),
        Some(s) if s.trim().is_empty() => "New Workspace".into(),
        Some(s) => s.trim().to_string(),
    }
}

fn workspace_exists(conn: &Connection, id: &str) -> Result<bool, WorkspaceError> {
    Ok(conn
        .query_row(
            "SELECT 1 FROM workspace WHERE id = ?1",
            [id],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| db_err(&e))?
        .is_some())
}

fn row_to_wire(conn: &Connection, data_dir: &Path, id: &str) -> Result<Value, WorkspaceError> {
    let (name, image, sort, created, updated): (String, Option<String>, i64, String, String) = conn
        .query_row(
            "SELECT name, imagePath, sortOrder, createdAt, updatedAt FROM workspace WHERE id = ?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
        )
        .optional()
        .map_err(|e| db_err(&e))?
        .ok_or_else(|| WorkspaceError::NotFound {
            id: id.to_string(),
        })?;
    Ok(wire_workspace(data_dir, id, &name, image, sort, &created, &updated))
}

fn wire_workspace(
    data_dir: &Path,
    id: &str,
    name: &str,
    image: Option<String>,
    sort: i64,
    created: &str,
    updated: &str,
) -> Value {
    let has_image = image
        .as_ref()
        .map(|p| managed_image_exists(data_dir, id, p))
        .unwrap_or(false);
    json!({
        "id": id,
        "name": name,
        "imagePath": image,
        "sortOrder": sort,
        "createdAt": created,
        "updatedAt": updated,
        "hasImage": has_image,
    })
}

fn images_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("Workspaces").join("Images")
}

fn store_image(data_dir: &Path, id: &str, b64: &str) -> Result<String, WorkspaceError> {
    use base64::Engine;
    let raw = base64::engine::general_purpose::STANDARD
        .decode(b64.trim())
        .map_err(|_| WorkspaceError::ImageInvalid)?;
    if raw.is_empty() {
        return Err(WorkspaceError::ImageInvalid);
    }
    let bytes = image::encode_avatar_png(&raw)?;
    let dir = images_dir(data_dir);
    std::fs::create_dir_all(&dir).map_err(|e| WorkspaceError::ImageIo {
        detail: format!("Failed to create workspace images directory: {e}"),
    })?;
  let file_name = format!("{id}.png");
    let path = dir.join(&file_name);
    std::fs::write(&path, bytes).map_err(|e| WorkspaceError::ImageIo {
        detail: format!("Failed to save workspace image: {e}"),
    })?;
    Ok(file_name)
}

fn clear_managed_image(conn: &Connection, data_dir: &Path, id: &str) -> Result<(), WorkspaceError> {
    let image: Option<String> = conn
        .query_row(
            "SELECT imagePath FROM workspace WHERE id = ?1",
            [id],
            |r| r.get::<_, Option<String>>(0),
        )
        .optional()
        .map_err(|e| db_err(&e))?
        .flatten();
    if let Some(p) = image {
        if !p.starts_with('/') {
            let path = images_dir(data_dir).join(&p);
            let _ = std::fs::remove_file(path);
        }
        conn.execute(
            "UPDATE workspace SET imagePath = NULL, updatedAt = ?1 WHERE id = ?2",
            rusqlite::params![now_grdb_datetime(), id],
        )
        .map_err(|e| db_err(&e))?;
    }
    Ok(())
}

fn managed_image_exists(data_dir: &Path, _id: &str, image_path: &str) -> bool {
    if image_path.starts_with('/') {
        return Path::new(image_path).exists();
    }
    images_dir(data_dir).join(image_path).exists()
}

fn check_stale(conn: &Connection, id: &str, expected: &Value) -> Result<(), WorkspaceError> {
    let current: String = conn
        .query_row(
            "SELECT updatedAt FROM workspace WHERE id = ?1",
            [id],
            |r| r.get(0),
        )
        .map_err(|e| db_err(&e))?;
    match expected {
        Value::String(s) if s == &current => Ok(()),
        _ => Err(WorkspaceError::ConflictStale),
    }
}

fn db_err(e: &rusqlite::Error) -> WorkspaceError {
    WorkspaceError::ImageIo {
        detail: e.to_string(),
    }
}
