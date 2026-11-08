use kuma_domain::StoreError;
use rusqlite::Connection;
use serde_json::{json, Map, Value};
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct DataPort {
    conn: Arc<Mutex<Connection>>,
    data_dir: std::path::PathBuf,
}

impl DataPort {
    pub fn new(conn: Arc<Mutex<Connection>>, data_dir: std::path::PathBuf) -> Self {
        Self { conn, data_dir }
    }

    pub fn export(&self) -> Result<Value, StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbBusy)?;
        Ok(json!({
            "version": 1,
            "workspaces": table_json(&conn, "workspace")?,
            "groups": table_json(&conn, "service_group")?,
            "services": table_json(&conn, "service")?,
            "providers": table_json(&conn, "provider")?,
            "kubeconfigs": table_json(&conn, "kube_config")?,
        }))
    }

    pub fn export_service_json(&self, service_id: &str) -> Result<Value, StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbBusy)?;
        let svc = conn
            .query_row(
                "SELECT rowid, * FROM service WHERE id = ?1",
                [service_id],
                row_to_map,
            )
            .map_err(|_| StoreError::ConstraintViolation {
                detail: format!("service {service_id} not found"),
            })?;
        Ok(json!({ "service": svc }))
    }

    pub fn import_preview(&self, bundle: &Map<String, Value>) -> Result<Value, StoreError> {
        let workspaces = bundle.get("workspaces").and_then(|v| v.as_array());
        Ok(json!({
            "strategy": "replace",
            "workspaceCount": workspaces.map(|a| a.len()).unwrap_or(0),
            "conflicts": [],
        }))
    }

    pub fn import(&self, bundle: &Map<String, Value>) -> Result<Value, StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbBusy)?;
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| StoreError::ConstraintViolation {
                detail: e.to_string(),
            })?;
        let mut counts = Map::new();
        for (table, key) in [
            ("workspace", "workspaces"),
            ("service_group", "groups"),
            ("service", "services"),
            ("provider", "providers"),
            ("kube_config", "kubeconfigs"),
        ] {
            if let Some(rows) = bundle.get(key).and_then(|v| v.as_array()) {
                for row in rows {
                    let Some(obj) = row.as_object() else { continue };
                    upsert_row(&tx, table, obj)?;
                }
                counts.insert(key.into(), json!(rows.len()));
            }
        }
        tx.commit().map_err(|e| StoreError::ConstraintViolation {
            detail: e.to_string(),
        })?;
        Ok(json!({ "imported": true, "counts": counts }))
    }

    pub fn factory_reset(&self) -> Result<Value, StoreError> {
        let conn = self.conn.lock().map_err(|_| StoreError::DbBusy)?;
        for table in [
            "provider",
            "service",
            "service_group",
            "service_group_membership",
            "workspace",
            "kube_config",
        ] {
            conn.execute(&format!("DELETE FROM \"{table}\""), [])
                .map_err(|e| StoreError::WipeFailed {
                    detail: e.to_string(),
                })?;
        }
        let images = self.data_dir.join("Workspaces").join("Images");
        if images.is_dir() {
            let _ = std::fs::remove_dir_all(&images);
        }
        let master = self.data_dir.join("master.key");
        Ok(json!({
            "reset": true,
            "masterKeyPreserved": master.exists(),
        }))
    }
}

fn table_json(conn: &Connection, table: &str) -> Result<Vec<Value>, StoreError> {
    let sql = format!("SELECT * FROM \"{table}\"");
    let mut stmt = conn
        .prepare(&sql)
        .map_err(|e| StoreError::RowDecode {
            table: table.into(),
            column: e.to_string(),
        })?;
    let col_count = stmt.column_count();
    let names: Vec<String> = (0..col_count)
        .map(|i| stmt.column_name(i).unwrap_or("").to_string())
        .collect();
    let rows = stmt
        .query_map([], |row| {
            let mut m = Map::new();
            for (i, name) in names.iter().enumerate() {
                let val: rusqlite::types::Value = row.get(i)?;
                m.insert(name.clone(), rusqlite_value_to_json(val));
            }
            Ok(Value::Object(m))
        })
        .map_err(|e| StoreError::RowDecode {
            table: table.into(),
            column: e.to_string(),
        })?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| StoreError::RowDecode {
            table: table.into(),
            column: e.to_string(),
        })
}

fn row_to_map(row: &rusqlite::Row<'_>) -> Result<Map<String, Value>, rusqlite::Error> {
    let mut m = Map::new();
    let count = row.as_ref().column_count();
    for i in 0..count {
        let name = row.as_ref().column_name(i)?.to_string();
        let val: rusqlite::types::Value = row.get(i)?;
        m.insert(name, rusqlite_value_to_json(val));
    }
    Ok(m)
}

fn rusqlite_value_to_json(v: rusqlite::types::Value) -> Value {
    match v {
        rusqlite::types::Value::Null => Value::Null,
        rusqlite::types::Value::Integer(i) => json!(i),
        rusqlite::types::Value::Real(f) => json!(f),
        rusqlite::types::Value::Text(s) => json!(s),
        rusqlite::types::Value::Blob(b) => json!(base64_encode(b)),
    }
}

fn base64_encode(b: Vec<u8>) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(b)
}

fn upsert_row(
    tx: &rusqlite::Transaction,
    table: &str,
    obj: &Map<String, Value>,
) -> Result<(), StoreError> {
    let Some(id) = obj.get("id").and_then(|v| v.as_str()) else {
        return Ok(());
    };
    let cols: Vec<&str> = obj.keys().map(String::as_str).collect();
    if cols.is_empty() {
        return Ok(());
    }
    let col_sql = cols
        .iter()
        .map(|c| format!("\"{c}\""))
        .collect::<Vec<_>>()
        .join(", ");
    let placeholders = (1..=cols.len())
        .map(|i| format!("?{i}"))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!("INSERT OR REPLACE INTO \"{table}\" ({col_sql}) VALUES ({placeholders})");
    let mut vals: Vec<String> = Vec::with_capacity(cols.len());
    for c in &cols {
        vals.push(json_to_text(obj.get(*c).unwrap_or(&Value::Null)));
    }
    let params: Vec<&str> = vals.iter().map(String::as_str).collect();
    tx.execute(&sql, rusqlite::params_from_iter(params))
        .map_err(|e| StoreError::ConstraintViolation {
            detail: format!("import {table} id={id}: {e}"),
        })?;
    Ok(())
}

fn json_to_text(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        Value::Bool(b) => {
            if *b {
                "1".into()
            } else {
                "0".into()
            }
        }
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}
