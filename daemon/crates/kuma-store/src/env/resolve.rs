use crate::env::path::PathResolver;
use crate::settings::{effective_for, expand_tilde, lookup, read_stored};
use rusqlite::Connection;
use crate::SettingsStore;
use serde_json::{json, Value};
use std::path::Path;

#[cfg(unix)]
fn is_executable_file(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| !m.is_dir() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable_file(p: &Path) -> bool {
    std::fs::metadata(p).map(|m| !m.is_dir()).unwrap_or(false)
}

pub fn resolve_executable(
    command: &str,
    custom_path: Option<&str>,
    apply_settings: bool,
    settings: &SettingsStore,
    path_resolver: &PathResolver,
) -> Value {
    let trimmed = command.trim();
    if trimmed.is_empty() {
        return json!({ "command": command, "path": Value::Null, "source": Value::Null });
    }

    if let Some(custom) = custom_path {
        let t = custom.trim();
        if !t.is_empty() {
            let expanded = expand_tilde(t);
            let path = Path::new(&expanded);
            if path.is_dir() {
                return json!({ "command": command, "path": Value::Null, "source": Value::Null });
            }
            if is_executable_file(path) {
                return json!({
                    "command": command,
                    "path": expanded,
                    "source": "settings"
                });
            }
            return json!({ "command": command, "path": Value::Null, "source": Value::Null });
        }
    }

    if apply_settings {
        if let Ok(v) = resolve_from_settings(trimmed, settings) {
            if !v["path"].is_null() {
                return v;
            }
        }
    }

    if trimmed.starts_with('/') {
        let p = Path::new(trimmed);
        if is_executable_file(p) {
            return json!({
                "command": command,
                "path": trimmed,
                "source": "absolute"
            });
        }
        return json!({ "command": command, "path": Value::Null, "source": Value::Null });
    }

    if trimmed.starts_with('~') {
        let expanded = expand_tilde(trimmed);
        if is_executable_file(Path::new(&expanded)) {
            return json!({
                "command": command,
                "path": expanded,
                "source": "absolute"
            });
        }
        return json!({ "command": command, "path": Value::Null, "source": Value::Null });
    }

    let path = path_resolver.resolve(false).path;
    for part in path.split(':').filter(|p| !p.is_empty()) {
        let candidate = Path::new(part).join(trimmed);
        if candidate.is_dir() {
            continue;
        }
        if is_executable_file(&candidate) {
            return json!({
                "command": command,
                "path": candidate.to_string_lossy(),
                "source": "path"
            });
        }
    }
    json!({ "command": command, "path": Value::Null, "source": Value::Null })
}

fn resolve_from_settings(command: &str, settings: &SettingsStore) -> Result<Value, ()> {
    let key = match command {
        "kubectl" => "kuma.settings.customKubectlPath",
        "docker" => "kuma.settings.customDockerPath",
        "podman" => "kuma.settings.customPodmanPath",
        "cloudflared" => "kuma.settings.cloudflaredPath",
        "ngrok" => "kuma.settings.customNgrokPath",
        _ => return Err(()),
    };
    let conn = settings.connection();
    let guard = conn.lock().map_err(|_| ())?;
    let def = lookup(key).ok_or(())?;
    let (effective, _) = effective_for(&guard, def).map_err(|_| ())?;
    let s = effective.as_str().unwrap_or("").trim();
    if s.is_empty() {
        return Err(());
    }
    let expanded = expand_tilde(s);
    if Path::new(&expanded).is_dir() {
        return Ok(json!({ "command": command, "path": Value::Null, "source": Value::Null }));
    }
    if is_executable_file(Path::new(&expanded)) {
        Ok(json!({
            "command": command,
            "path": expanded,
            "source": "settings"
        }))
    } else {
        Ok(json!({ "command": command, "path": Value::Null, "source": Value::Null }))
    }
}

pub fn read_settings_path(conn: &Connection, primary: &str, legacy: Option<&str>) -> String {
    if let Some(def) = lookup(primary) {
        if let Ok((v, _)) = effective_for(conn, def) {
            return v.as_str().unwrap_or("").trim().to_string();
        }
    }
    if let Some(fb) = legacy {
        if let Ok(Some(v)) = read_stored(conn, fb) {
            return v.as_str().unwrap_or("").trim().to_string();
        }
    }
    String::new()
}
