use crate::runtime::ExecError;
use serde_json::Value;
use std::path::PathBuf;

/// DEV-75: ephemeral YAML under `runtime/compose/<SERVICEID>/docker-compose.kuma.yml`.
pub fn materialize_compose_file(
    service_id: &str,
    provider: &Value,
) -> Result<(PathBuf, bool), ExecError> {
    if let Some(path) = provider
        .get("composeFilePath")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        return Ok((PathBuf::from(path), false));
    }
    let yaml = provider
        .get("yamlConfig")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ExecError::Message("compose provider missing file or yaml".into()))?;
    let dir = kuma_protocol::paths::runtime_dir()
        .join("compose")
        .join(service_id.to_uppercase());
    std::fs::create_dir_all(&dir).map_err(|e| ExecError::Message(e.to_string()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700));
    }
    let file = dir.join("docker-compose.kuma.yml");
    std::fs::write(&file, yaml.as_bytes()).map_err(|e| ExecError::Message(e.to_string()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o600));
    }
    Ok((file, true))
}

pub fn remove_ephemeral_compose(service_id: &str) {
    let dir = kuma_protocol::paths::runtime_dir()
        .join("compose")
        .join(service_id.to_uppercase());
    let _ = std::fs::remove_dir_all(dir);
}
