use crate::settings::registry::{default_json, enum_values_json, lookup, KeyDef, KeyKind};
use kuma_domain::SettingsError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Value};

pub fn trim_ws(s: &str) -> String {
    s.trim_matches(|c: char| c.is_whitespace()).to_string()
}

pub fn read_stored(conn: &Connection, key: &str) -> Result<Option<Value>, SettingsError> {
    let raw: Option<String> = conn
        .query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| r.get(0))
        .optional()
        .map_err(|e| SettingsError::InvalidValue {
            key: key.into(),
            message: e.to_string(),
        })?;
    let Some(text) = raw else {
        return Ok(None);
    };
    match serde_json::from_str::<Value>(&text) {
        Ok(v) => Ok(Some(v)),
        Err(_) => Ok(None),
    }
}

pub fn read_updated_at(conn: &Connection, key: &str) -> Result<Option<String>, SettingsError> {
    conn.query_row("SELECT updatedAt FROM settings WHERE key = ?1", [key], |r| r.get(0))
        .optional()
        .map_err(|e| SettingsError::InvalidValue {
            key: key.into(),
            message: e.to_string(),
        })
}

fn string_effective(
    conn: &Connection,
    primary: &str,
    legacy: Option<&str>,
) -> Result<(Value, &'static str), SettingsError> {
    if let Some(v) = read_stored(conn, primary)? {
        if let Value::String(s) = v {
            let t = trim_ws(&s);
            if !t.is_empty() {
                return Ok((Value::String(s), "stored"));
            }
        } else {
            return Ok((v, "stored"));
        }
    }
    if let Some(fb) = legacy {
        if let Some(Value::String(s)) = read_stored(conn, fb)? {
            let t = trim_ws(&s);
            if !t.is_empty() {
                return Ok((Value::String(s), "legacy"));
            }
        }
    }
    Ok((json!(""), "default"))
}

fn bool_effective(
    conn: &Connection,
    primary: &str,
    default: bool,
    legacy: Option<&str>,
) -> Result<(Value, &'static str), SettingsError> {
    if let Some(v) = read_stored(conn, primary)? {
        if let Some(b) = v.as_bool() {
            return Ok((json!(b), "stored"));
        }
    }
    if let Some(fb) = legacy {
        if let Some(v) = read_stored(conn, fb)? {
            if let Some(b) = v.as_bool() {
                return Ok((json!(b), "legacy"));
            }
        }
    }
    Ok((json!(default), "default"))
}

pub fn effective_for(conn: &Connection, def: &KeyDef) -> Result<(Value, &'static str), SettingsError> {
    match def.key {
        "kuma.has_completed_onboarding" | "kuma.settings.launchAtLogin" | "kuma.settings.autoResumeServices" => {
            bool_effective(conn, def.key, false, None)
        }
        "kuma.settings.confirmBeforeQuit" => bool_effective(conn, def.key, true, None),
        "kuma.settings.notifyOnServiceFailure" => {
            bool_effective(conn, def.key, true, Some("kuma.settings.notifyOnCrash"))
        }
        "kuma.settings.activeServiceIDsBeforeQuit" => {
            if let Some(v) = read_stored(conn, def.key)? {
                return Ok((v, "stored"));
            }
            Ok((json!([]), "default"))
        }
        "kuma.settings.quitBehavior" => {
            if read_stored(conn, def.key)?.is_some() {
                let (eff, _) = enum_effective(conn, def, "ask")?;
                return Ok((eff, "stored"));
            }
            Ok((json!("ask"), "default"))
        }
        "kuma.settings.appearance" => enum_effective(conn, def, "system"),
        "kuma.settings.portConflictPolicy" => enum_effective(conn, def, "warn_and_block"),
        "kuma.settings.defaultShell" => {
            if let Some(v) = read_stored(conn, def.key)? {
                return Ok((v, "stored"));
            }
            Ok((json!("/bin/zsh"), "default"))
        }
        _ if def.is_tool_path && !def.is_kubeconfig_path => {
            string_effective(conn, def.key, def.legacy)
        }
        "kuma.settings.customKubeconfigPath" => string_effective(conn, def.key, def.legacy),
        "kuma.selectedWorkspaceId.storage" | "kuma.settings.notifyOnCrash" => {
            if let Some(v) = read_stored(conn, def.key)? {
                return Ok((v, "stored"));
            }
            Ok((Value::Null, "default"))
        }
        _ if def.kind == KeyKind::Any => {
            if let Some(v) = read_stored(conn, def.key)? {
                return Ok((v, "stored"));
            }
            Ok((Value::Null, "default"))
        }
        _ if def.legacy.is_some() => string_effective(conn, def.key, def.legacy),
        _ => {
            if let Some(v) = read_stored(conn, def.key)? {
                Ok((v, "stored"))
            } else {
                Ok((default_json(def), "default"))
            }
        }
    }
}

fn enum_effective(
    conn: &Connection,
    def: &KeyDef,
    default: &str,
) -> Result<(Value, &'static str), SettingsError> {
    let allowed = def.enum_values.unwrap_or(&[]);
    if let Some(v) = read_stored(conn, def.key)? {
        if let Some(s) = v.as_str() {
            if allowed.contains(&s) {
                return Ok((json!(s), "stored"));
            }
            return Ok((json!(default), "default"));
        }
    }
    Ok((json!(default), "default"))
}

pub fn build_setting(conn: &Connection, def: &KeyDef) -> Result<Value, SettingsError> {
    build_setting_for_key(conn, def.key, Some(def))
}

pub fn build_setting_for_key(
    conn: &Connection,
    key: &str,
    def: Option<&KeyDef>,
) -> Result<Value, SettingsError> {
    if key.starts_with("client.") {
        let stored = read_stored(conn, key)?;
        let updated = read_updated_at(conn, key)?;
        return Ok(json!({
            "key": key,
            "type": "any",
            "interpreter": "client",
            "stored": stored,
            "effective": stored.clone().unwrap_or(Value::Null),
            "default": Value::Null,
            "source": if stored.is_some() { "stored" } else { "default" },
            "updatedAt": updated,
        }));
    }
    let def = def.or_else(|| lookup(key)).ok_or_else(|| SettingsError::UnknownKey {
        key: key.into(),
    })?;
    let stored = read_stored(conn, def.key)?;
    let (effective, source) = effective_for(conn, def)?;
    let updated = read_updated_at(conn, def.key)?;
    Ok(json!({
        "key": def.key,
        "type": def.wire_type,
        "enumValues": enum_values_json(def),
        "interpreter": def.interpreter,
        "stored": stored,
        "effective": effective,
        "default": default_json(def),
        "source": source,
        "updatedAt": updated,
    }))
}
