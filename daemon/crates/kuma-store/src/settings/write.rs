use crate::settings::change::SettingsChangeSink;
use crate::settings::effective::{build_setting_for_key, read_stored, read_updated_at, trim_ws};
use crate::settings::registry::{lookup, KeyDef, KeyKind, REGISTRY};
use crate::settings::time::{format_wire_timestamp, parse_wire_timestamp};
use chrono::Duration;
use crate::settings::validate::{
    strict_error_message, strict_kubeconfig_message, validate_custom_binary,
    validate_kubeconfig_path, Validation,
};
use kuma_domain::SettingsError;
use rusqlite::Connection;
use serde_json::{json, Map, Value};
use std::collections::HashSet;
use uuid::Uuid;

const MAX_CLIENT_VALUE_BYTES: usize = 65536;

#[derive(Debug)]
pub struct SetResult {
    pub updated: Vec<Value>,
    pub removed: Vec<String>,
    pub validation: Map<String, Value>,
    pub changed_keys: Vec<String>,
}

fn notify_on_crash_key() -> &'static str {
    "kuma.settings.notifyOnCrash"
}

pub fn coerce_bool(key: &str, v: &Value) -> Result<bool, SettingsError> {
    match v {
        Value::Bool(b) => Ok(*b),
        Value::Number(n) => {
            if n.as_i64() == Some(0) {
                Ok(false)
            } else if n.as_i64() == Some(1) {
                Ok(true)
            } else {
                Err(SettingsError::InvalidType {
                    key: key.into(),
                    expected: "bool".into(),
                })
            }
        }
        Value::String(s) => {
            let lower = s.to_ascii_lowercase();
            match lower.as_str() {
                "true" | "1" | "yes" => Ok(true),
                "false" | "0" | "no" => Ok(false),
                _ => Err(SettingsError::InvalidType {
                    key: key.into(),
                    expected: "bool".into(),
                }),
            }
        }
        _ => Err(SettingsError::InvalidType {
            key: key.into(),
            expected: "bool".into(),
        }),
    }
}

fn coerce_enum(key: &str, v: &Value, allowed: &[&str]) -> Result<String, SettingsError> {
    let Value::String(s) = v else {
        return Err(SettingsError::InvalidType {
            key: key.into(),
            expected: "enum string".into(),
        });
    };
    if allowed.contains(&s.as_str()) {
        Ok(s.clone())
    } else {
        Err(SettingsError::InvalidValue {
            key: key.into(),
            message: format!("must be one of: {}", allowed.join(", ")),
        })
    }
}

fn parse_uuid_item(key: &str, s: &str) -> Result<String, SettingsError> {
    Uuid::parse_str(s.trim()).map(|u| u.to_string().to_uppercase()).map_err(|_| {
        SettingsError::InvalidValue {
            key: key.into(),
            message: "invalid UUID in array".into(),
        }
    })
}

fn coerce_value(key: &str, v: &Value, def: Option<&KeyDef>) -> Result<Option<Value>, SettingsError> {
    if v.is_null() {
        return Ok(None);
    }
    if key.starts_with("client.") {
        let text = serde_json::to_string(v).map_err(|_| SettingsError::InvalidValue {
            key: key.into(),
            message: "invalid JSON".into(),
        })?;
        if text.len() > MAX_CLIENT_VALUE_BYTES {
            return Err(SettingsError::ValueTooLarge { key: key.into() });
        }
        return Ok(Some(v.clone()));
    }
    let def = def.ok_or_else(|| SettingsError::UnknownKey { key: key.into() })?;
    match def.kind {
        KeyKind::Bool => Ok(Some(json!(coerce_bool(key, v)?))),
        KeyKind::StringEnum => {
            let allowed = def.enum_values.unwrap_or(&[]);
            Ok(Some(json!(coerce_enum(key, v, allowed)?)))
        }
        KeyKind::String => {
            let Value::String(s) = v else {
                return Err(SettingsError::InvalidType {
                    key: key.into(),
                    expected: "string".into(),
                });
            };
            if def.key == "kuma.selectedWorkspaceId.storage" {
                let upper = parse_uuid_item(key, s)?;
                return Ok(Some(json!(upper)));
            }
            if def.is_tool_path && !def.is_kubeconfig_path {
                return Ok(Some(json!(trim_ws(s))));
            }
            Ok(Some(json!(s.clone())))
        }
        KeyKind::StringArray => {
            let Value::Array(arr) = v else {
                return Err(SettingsError::InvalidType {
                    key: key.into(),
                    expected: "string array".into(),
                });
            };
            let mut out = Vec::new();
            for item in arr {
                let Value::String(s) = item else {
                    return Err(SettingsError::InvalidType {
                        key: key.into(),
                        expected: "string array".into(),
                    });
                };
                out.push(parse_uuid_item(key, s)?);
            }
            Ok(Some(json!(out)))
        }
        KeyKind::Any => Ok(Some(v.clone())),
    }
}

fn validation_for_path(def: &KeyDef, stored: &str) -> Validation {
    if def.is_kubeconfig_path {
        validate_kubeconfig_path(stored)
    } else if let Some(cmd) = def.tool_command {
        validate_custom_binary(stored, cmd)
    } else {
        Validation::empty()
    }
}

fn strict_check(def: &KeyDef, trimmed: &str) -> Result<(), SettingsError> {
    if trimmed.is_empty() {
        return Ok(());
    }
    if def.is_kubeconfig_path {
        let v = validate_kubeconfig_path(trimmed);
        if !v.is_valid && v.status != "empty" {
            return Err(SettingsError::PathInvalid {
                key: def.key.into(),
                message: strict_kubeconfig_message().into(),
            });
        }
    } else if def.is_tool_path {
        if let Some(cmd) = def.tool_command {
            let v = validate_custom_binary(trimmed, cmd);
            if !v.is_valid && v.status != "empty" {
                return Err(SettingsError::PathInvalid {
                    key: def.key.into(),
                    message: strict_error_message(&v),
                });
            }
        }
    }
    Ok(())
}

fn check_expected(
    conn: &Connection,
    key: &str,
    expected: &Value,
) -> Result<(), SettingsError> {
    let current = read_updated_at(conn, key)?;
    match expected {
        Value::Null => {
            if current.is_some() {
                return Err(SettingsError::ConflictStale { key: key.into() });
            }
        }
        Value::String(ts) => {
            if current.as_deref() != Some(ts.as_str()) {
                return Err(SettingsError::ConflictStale { key: key.into() });
            }
        }
        _ => {
            return Err(SettingsError::InvalidValue {
                key: key.into(),
                message: "expectedUpdatedAt must be string or null".into(),
            });
        }
    }
    Ok(())
}

fn canonical_stored(v: &Value) -> String {
    serde_json::to_string(v).unwrap_or_default()
}

fn extra_deletes_for_write(key: &str, delete: bool) -> Vec<String> {
    let mut out = Vec::new();
    if key == "kuma.settings.notifyOnServiceFailure" {
        out.push(notify_on_crash_key().into());
    }
    if let Some(def) = lookup(key) {
        if def.is_tool_path || delete {
            if let Some(leg) = def.legacy {
                out.push(leg.into());
            }
        }
    }
    out
}

/// DT-SET-35: deleting notifyOnCrash when writing notifyOnServiceFailure even if value unchanged.
fn force_side_effect_keys(key: &str, conn: &Connection) -> Vec<String> {
    if key == "kuma.settings.notifyOnServiceFailure"
        && read_stored(conn, notify_on_crash_key())
            .ok()
            .flatten()
            .is_some()
    {
        return vec![notify_on_crash_key().into()];
    }
    Vec::new()
}

pub fn set_values(
    conn: &mut Connection,
    values: &Map<String, Value>,
    strict: bool,
    expected_updated_at: Option<&Map<String, Value>>,
    sink: &dyn SettingsChangeSink,
) -> Result<SetResult, SettingsError> {
    if let Some(exp) = expected_updated_at {
        for (key, ts) in exp {
            check_expected(conn, key, ts)?;
        }
    }

    let mut validation_map = Map::new();
    let mut ops: Vec<(String, Option<Value>)> = Vec::new();
    let mut extra_deletes: HashSet<String> = HashSet::new();

    for (key, raw) in values {
        let def = if key.starts_with("client.") {
            None
        } else {
            Some(lookup(key).ok_or_else(|| SettingsError::UnknownKey { key: key.clone() })?)
        };

        if raw.is_null() {
            ops.push((key.clone(), None));
            for d in extra_deletes_for_write(key, true) {
                extra_deletes.insert(d);
            }
            continue;
        }

        let coerced = coerce_value(key, raw, def)?;
        let Some(stored) = coerced else {
            continue;
        };

        if let Some(def) = def {
            if strict && (def.is_tool_path || def.is_kubeconfig_path) {
                let s = stored.as_str().unwrap_or("");
                strict_check(def, s)?;
            }
            if def.is_tool_path && validation_map.get(key).is_none() {
                let path = stored.as_str().unwrap_or("");
                let v = validation_for_path(def, path);
                validation_map.insert(
                    key.clone(),
                    v.to_json(Some(path.to_string())),
                );
            }
        }

        for d in extra_deletes_for_write(key, false) {
            extra_deletes.insert(d);
        }
        ops.push((key.clone(), Some(stored)));
    }

    let mut changed_keys: HashSet<String> = HashSet::new();
    let mut removed: Vec<String> = Vec::new();
    let mut any_change = false;

    for (key, new_val) in &ops {
        match new_val {
            None => {
                if read_stored(conn, key)?.is_some() {
                    any_change = true;
                    changed_keys.insert(key.clone());
                    removed.push(key.clone());
                }
                for d in extra_deletes_for_write(key, true) {
                    if read_stored(conn, &d)?.is_some() {
                        any_change = true;
                        extra_deletes.insert(d);
                    }
                }
            }
            Some(v) => {
                let prev = read_stored(conn, key)?;
                if prev.as_ref().map(canonical_stored) != Some(canonical_stored(v)) {
                    any_change = true;
                    changed_keys.insert(key.clone());
                }
                for fk in force_side_effect_keys(key, conn) {
                    if read_stored(conn, &fk)?.is_some() {
                        any_change = true;
                        extra_deletes.insert(fk);
                    }
                }
            }
        }
    }
    for d in &extra_deletes {
        if read_stored(conn, d)?.is_some() {
            any_change = true;
            changed_keys.insert(d.clone());
            if !removed.contains(d) {
                removed.push(d.clone());
            }
        }
    }

    if !any_change {
        let mut updated = Vec::new();
        for (key, _) in &ops {
            updated.push(build_setting_for_key(conn, key, lookup(key))?);
        }
        return Ok(SetResult {
            updated,
            removed: vec![],
            validation: validation_map,
            changed_keys: vec![],
        });
    }

    let mut max_prev = String::new();
    for (key, new_val) in &ops {
        if new_val.is_none() {
            continue;
        }
        if let Ok(Some(prev)) = read_updated_at(conn, key) {
            if prev > max_prev {
                max_prev = prev;
            }
        }
    }
    let ts = if max_prev.is_empty() {
        format_wire_timestamp(chrono::Utc::now())
    } else if let Some(dt) = parse_wire_timestamp(&max_prev) {
        format_wire_timestamp(dt + Duration::milliseconds(1))
    } else {
        format_wire_timestamp(chrono::Utc::now())
    };
    let tx = conn
        .transaction()
        .map_err(|e| SettingsError::InvalidValue {
            key: "transaction".into(),
            message: e.to_string(),
        })?;

    for (key, new_val) in &ops {
        match new_val {
            None => {
                tx.execute("DELETE FROM settings WHERE key = ?1", [key.as_str()])
                    .map_err(|e| SettingsError::InvalidValue {
                        key: key.clone(),
                        message: e.to_string(),
                    })?;
            }
            Some(v) => {
                let text = canonical_stored(v);
                tx.execute(
                    "INSERT INTO settings (key, value, updatedAt) VALUES (?1, ?2, ?3)
                     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt",
                    rusqlite::params![key, text, ts],
                )
                .map_err(|e| SettingsError::InvalidValue {
                    key: key.clone(),
                    message: e.to_string(),
                })?;
            }
        }
        for d in extra_deletes_for_write(key, new_val.is_none()) {
            let _ = tx.execute("DELETE FROM settings WHERE key = ?1", [d.as_str()]);
        }
    }
    for d in &extra_deletes {
        tx.execute("DELETE FROM settings WHERE key = ?1", [d.as_str()])
            .map_err(|e| SettingsError::InvalidValue {
                key: d.clone(),
                message: e.to_string(),
            })?;
    }

    tx.commit().map_err(|e| SettingsError::InvalidValue {
        key: "commit".into(),
        message: e.to_string(),
    })?;

    let mut updated = Vec::new();
    for (key, new_val) in &ops {
        if new_val.is_some() {
            updated.push(build_setting_for_key(conn, key, lookup(key))?);
        }
    }

    let changed: Vec<String> = changed_keys.into_iter().collect();
    let _ = sink;

    Ok(SetResult {
        updated,
        removed,
        validation: validation_map,
        changed_keys: changed,
    })
}

pub fn list_client_keys(conn: &Connection) -> Result<Vec<String>, SettingsError> {
    let mut stmt = conn
        .prepare("SELECT key FROM settings WHERE key LIKE 'client.%' ORDER BY key")
        .map_err(|e| SettingsError::InvalidValue {
            key: "client".into(),
            message: e.to_string(),
        })?;
    let keys = stmt
        .query_map([], |r| r.get::<_, String>(0))
        .map_err(|e| SettingsError::InvalidValue {
            key: "client".into(),
            message: e.to_string(),
        })?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| SettingsError::InvalidValue {
            key: "client".into(),
            message: e.to_string(),
        })?;
    Ok(keys)
}

pub fn list_all_settings(
    conn: &Connection,
    prefix: Option<&str>,
    include_client: bool,
) -> Result<Vec<Value>, SettingsError> {
    let mut out = Vec::new();
    for def in REGISTRY.iter() {
        if let Some(p) = prefix {
            if !def.key.starts_with(p) {
                continue;
            }
        }
        out.push(crate::settings::effective::build_setting(conn, def)?);
    }
    if include_client {
        let want_client = match prefix {
            None => true,
            Some(p) => "client.".starts_with(p) || p.starts_with("client."),
        };
        if want_client {
            for key in list_client_keys(conn)? {
                if let Some(p) = prefix {
                    if !key.starts_with(p) {
                        continue;
                    }
                }
                out.push(build_setting_for_key(conn, &key, None)?);
            }
        }
    }
    Ok(out)
}
