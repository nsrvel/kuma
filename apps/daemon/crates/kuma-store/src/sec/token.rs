use kuma_domain::StoreError;
use std::path::{Path, PathBuf};

pub fn api_token_path(data_dir: &Path) -> PathBuf {
    data_dir.join("api-token")
}

pub fn ensure_api_token(data_dir: &Path) -> Result<(), StoreError> {
    let path = api_token_path(data_dir);
    if path.exists() {
        set_mode(&path, 0o600)?;
        return Ok(());
    }
    let token = random_hex_token()?;
    let body = format!("{token}\n");
    std::fs::write(&path, body).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    set_mode(&path, 0o600)
}

pub fn rotate_api_token(data_dir: &Path) -> Result<serde_json::Value, StoreError> {
    let path = api_token_path(data_dir);
    let token = random_hex_token()?;
    let tmp = data_dir.join(".api-token.tmp");
    let body = format!("{token}\n");
    std::fs::write(&tmp, &body).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    set_mode(&tmp, 0o600)?;
    std::fs::rename(&tmp, &path).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    let now = chrono::Utc::now()
        .format("%Y-%m-%dT%H:%M:%S%.3fZ")
        .to_string();
    Ok(serde_json::json!({
        "tokenPath": path.display().to_string(),
        "rotatedAt": now,
    }))
}

fn random_hex_token() -> Result<String, StoreError> {
    use std::io::Read;
    let mut buf = [0u8; 32];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut buf))
        .map_err(|e| StoreError::DbOpenFailed {
            detail: e.to_string(),
        })?;
    Ok(buf.iter().map(|b| format!("{b:02x}")).collect())
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) -> Result<(), StoreError> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode)).map_err(|e| {
        StoreError::DbOpenFailed {
            detail: e.to_string(),
        }
    })
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) -> Result<(), StoreError> {
    Ok(())
}
