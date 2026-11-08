use std::path::{Path, PathBuf};

/// Override application data root (`KUMA_DATA_DIR`).
pub fn data_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("KUMA_DATA_DIR") {
        return PathBuf::from(dir);
    }
    default_data_dir()
}

/// Runtime directory: `KUMA_RUNTIME_DIR` or `<dataDir>/run/` (spec 10 §2.2).
pub fn runtime_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("KUMA_RUNTIME_DIR") {
        return PathBuf::from(dir);
    }
    data_dir().join("run")
}

pub fn socket_path() -> PathBuf {
    runtime_dir().join("kuma-daemon.sock")
}

pub fn pid_file_path() -> PathBuf {
    runtime_dir().join("kuma-daemon.pid")
}

pub fn lock_file_path() -> PathBuf {
    runtime_dir().join("kuma-daemon.lock")
}

fn default_data_dir() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join("Kuma");
        }
    }
    std::env::temp_dir().join("Kuma")
}

/// Create runtime dir with mode `0700` (best effort on non-Unix).
pub fn ensure_runtime_dir() -> std::io::Result<()> {
    let dir = runtime_dir();
    std::fs::create_dir_all(&dir)?;
    set_mode(dir.as_path(), 0o700)
}

fn set_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
    }
    #[cfg(not(unix))]
    {
        let _ = (path, mode);
        Ok(())
    }
}

pub fn set_path_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    set_mode(path, mode)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{LazyLock, Mutex};

    static ENV_LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

    #[test]
    fn runtime_under_data_by_default() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::remove_var("KUMA_DATA_DIR");
        std::env::remove_var("KUMA_RUNTIME_DIR");
        let rt = runtime_dir();
        assert!(rt.ends_with("run"));
        assert!(rt.parent().unwrap().ends_with("Kuma") || rt.to_string_lossy().contains("Kuma"));
    }

    #[test]
    fn overrides() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::remove_var("KUMA_RUNTIME_DIR");
        std::env::set_var("KUMA_DATA_DIR", "/tmp/kuma-data-test");
        assert_eq!(runtime_dir(), PathBuf::from("/tmp/kuma-data-test/run"));
        assert_eq!(
            socket_path(),
            PathBuf::from("/tmp/kuma-data-test/run/kuma-daemon.sock")
        );
        std::env::remove_var("KUMA_DATA_DIR");
    }

    #[test]
    fn runtime_dir_override() {
        let _g = ENV_LOCK.lock().unwrap();
        std::env::set_var("KUMA_RUNTIME_DIR", "/tmp/kuma-rt-only");
        assert_eq!(socket_path(), PathBuf::from("/tmp/kuma-rt-only/kuma-daemon.sock"));
        std::env::remove_var("KUMA_RUNTIME_DIR");
    }
}
