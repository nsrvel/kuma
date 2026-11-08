//! ADD-09 legacy UserDefaults plist import ([03 §3.8](docs/specs/daemon/03-settings-and-environment.md)).

use crate::settings::{KeyKind, REGISTRY, now_wire_timestamp};
use kuma_domain::StoreError;
use plist::Value as PlistValue;
use rusqlite::{Connection, OptionalExtension};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

const META_LEGACY_IMPORT_DONE: &str = "legacyImportDone";

pub fn run_legacy_import(conn: &Connection) -> Result<(), StoreError> {
    if meta_get(conn, META_LEGACY_IMPORT_DONE)?.is_some() {
        return Ok(());
    }

    #[cfg(not(target_os = "macos"))]
    {
        mark_done(conn)?;
        return Ok(());
    }

    #[cfg(target_os = "macos")]
    {
        let Some(plist_path) = locate_plist() else {
            mark_done(conn)?;
            tracing::info!("legacy import: no plist");
            return Ok(());
        };
        if !plist_path.exists() {
            mark_done(conn)?;
            tracing::info!("legacy import: no plist");
            return Ok(());
        }

        let dict = match read_plist_dict(&plist_path) {
            Ok(Some(d)) => d,
            Ok(None) | Err(_) => {
                tracing::warn!(path = %plist_path.display(), "legacy import: corrupt or unreadable plist");
                return Ok(());
            }
        };

        import_dict(conn, &dict)?;
        mark_done(conn)?;
    }

    Ok(())
}

fn import_dict(conn: &Connection, dict: &HashMap<String, PlistValue>) -> Result<(), StoreError> {
    let ts = now_wire_timestamp();
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;

    for def in REGISTRY.iter() {
        let Some(plist_val) = dict.get(def.key) else {
            continue;
        };
        let Some(json) = plist_to_json(def, plist_val) else {
            tracing::warn!(key = def.key, "legacy import: skipped key");
            continue;
        };
        let text = serde_json::to_string(&json).map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
        let _ = tx.execute(
            "INSERT OR IGNORE INTO settings (key, value, updatedAt) VALUES (?1, ?2, ?3)",
            rusqlite::params![def.key, text, ts],
        );
    }

    tx.execute(
        "INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![META_LEGACY_IMPORT_DONE, ts],
    )
    .map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;

    tx.commit().map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    Ok(())
}

fn meta_get(conn: &Connection, key: &str) -> Result<Option<String>, StoreError> {
    conn.query_row("SELECT value FROM meta WHERE key = ?1", [key], |r| r.get(0))
        .optional()
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })
}

fn mark_done(conn: &Connection) -> Result<(), StoreError> {
    let ts = now_wire_timestamp();
    conn.execute(
        "INSERT INTO meta (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![META_LEGACY_IMPORT_DONE, ts],
    )
    .map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    Ok(())
}

#[cfg(target_os = "macos")]
fn locate_plist() -> Option<PathBuf> {
    if let Ok(override_path) = std::env::var("KUMA_LEGACY_DEFAULTS_PLIST") {
        if !override_path.is_empty() {
            return Some(PathBuf::from(override_path));
        }
    }
    real_home().map(|h| h.join("Library/Preferences/com.kuma.Kuma.plist"))
}

#[cfg(target_os = "macos")]
fn real_home() -> Option<PathBuf> {
    unsafe {
        libc::getpwuid(libc::getuid())
            .as_ref()
            .and_then(|pw| {
                if pw.pw_dir.is_null() {
                    None
                } else {
                    Some(PathBuf::from(
                        std::ffi::CStr::from_ptr(pw.pw_dir)
                            .to_string_lossy()
                            .into_owned(),
                    ))
                }
            })
    }
}

#[cfg(target_os = "macos")]
fn read_plist_dict(path: &Path) -> Result<Option<HashMap<String, PlistValue>>, StoreError> {
    let file = std::fs::File::open(path).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    let root: PlistValue = plist::from_reader(file).map_err(|_| StoreError::DbOpenFailed {
        detail: "plist parse".into(),
    })?;
    match root {
        PlistValue::Dictionary(d) => Ok(Some(d.into_iter().collect())),
        _ => Ok(None),
    }
}

fn plist_to_json(
    def: &crate::settings::KeyDef,
    v: &PlistValue,
) -> Option<serde_json::Value> {
    use serde_json::json;
    use uuid::Uuid;
    match def.kind {
        KeyKind::Bool => {
            let b = plist_bool(v)?;
            Some(json!(b))
        }
        KeyKind::StringEnum => {
            let PlistValue::String(s) = v else {
                return None;
            };
            let allowed = def.enum_values.unwrap_or(&[]);
            if allowed.contains(&s.as_str()) {
                Some(json!(s))
            } else {
                None
            }
        }
        KeyKind::String => {
            let PlistValue::String(s) = v else {
                return None;
            };
            if def.key == "kuma.selectedWorkspaceId.storage" {
                let upper = Uuid::parse_str(s.trim()).ok()?.to_string().to_uppercase();
                return Some(json!(upper));
            }
            if def.is_tool_path {
                return Some(json!(s.trim()));
            }
            Some(json!(s))
        }
        KeyKind::StringArray => {
            let PlistValue::Array(arr) = v else {
                return None;
            };
            let mut out = Vec::new();
            for item in arr {
                let PlistValue::String(s) = item else {
                    continue;
                };
                if let Ok(u) = Uuid::parse_str(s.trim()) {
                    out.push(u.to_string().to_uppercase());
                }
            }
            Some(json!(out))
        }
        KeyKind::Any => plist_scalar_json(v),
    }
}

fn plist_scalar_json(v: &PlistValue) -> Option<serde_json::Value> {
    use serde_json::json;
    match v {
        PlistValue::Boolean(b) => Some(json!(*b)),
        PlistValue::Integer(i) => i.as_signed().map(|n| json!(n)),
        PlistValue::Real(r) => Some(json!(*r)),
        PlistValue::String(s) => Some(json!(s)),
        _ => None,
    }
}

fn plist_bool(v: &PlistValue) -> Option<bool> {
    match v {
        PlistValue::Boolean(b) => Some(*b),
        PlistValue::Integer(i) => i.as_signed().map(|n| n != 0),
        PlistValue::String(s) => Some(nsstring_bool_value(s)),
        _ => None,
    }
}

/// NSString `boolValue` approximation ([03 §3.8.4](docs/specs/daemon/03-settings-and-environment.md)).
fn nsstring_bool_value(s: &str) -> bool {
    let t = s.trim_start();
    let mut chars = t.chars();
    if matches!(chars.clone().next(), Some('+' | '-')) {
        chars.next();
    }
    while chars.clone().next().is_some_and(|c| c == '0') {
        chars.next();
    }
    matches!(chars.next(), Some(c) if matches!(c, 'Y' | 'y' | 'T' | 't' | '1'..='9'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nsstring_bool_yes_no() {
        assert!(nsstring_bool_value("YES"));
        assert!(!nsstring_bool_value("corrupted_value_xyz"));
        assert!(!nsstring_bool_value("0"));
    }
}
