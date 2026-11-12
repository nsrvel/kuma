use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::io::AsRawFd;
use std::path::Path;

use anyhow::{bail, Context, Result};
use kuma_protocol::jsonrpc::{Request, Response};
use kuma_protocol::methods;
use kuma_protocol::paths;

pub struct InstanceLock {
    _file: File,
}

impl InstanceLock {
    pub fn acquire() -> Result<Self> {
        paths::ensure_runtime_dir().context("runtime dir")?;
        let path = paths::lock_file_path();
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(&path)
            .with_context(|| format!("open lock file {}", path.display()))?;

        let fd = file.as_raw_fd();
        let rc = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
        if rc != 0 {
            if probe_live_daemon(&paths::socket_path()) {
                bail!("kuma daemon already running (lock held or socket active)");
            }
            // Stale lock file without a live holder — retry once after removing lock path.
            drop(file);
            let _ = std::fs::remove_file(&path);
            let file = OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(false)
                .open(&path)
                .context("reopen lock file")?;
            let fd = file.as_raw_fd();
            let rc = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
            if rc != 0 {
                bail!("could not acquire daemon lock");
            }
            return Ok(Self { _file: file });
        }
        Ok(Self { _file: file })
    }
}

impl Drop for InstanceLock {
    fn drop(&mut self) {
        let fd = self._file.as_raw_fd();
        unsafe {
            libc::flock(fd, libc::LOCK_UN);
        }
    }
}

pub fn prepare_stale_socket() -> Result<()> {
    let socket = paths::socket_path();
    if !socket.exists() {
        return Ok(());
    }
    if probe_live_daemon(&socket) {
        bail!("kuma daemon already running");
    }
    std::fs::remove_file(&socket).context("remove stale socket")?;
    Ok(())
}

fn probe_live_daemon(socket: &Path) -> bool {
    let Ok(mut stream) = std::os::unix::net::UnixStream::connect(socket) else {
        return false;
    };
    let req = Request {
        jsonrpc: "2.0".into(),
        method: methods::DAEMON_PING.into(),
        params: serde_json::json!({}),
        id: Some(1.into()),
    };
    let Ok(line) = serde_json::to_string(&req) else {
        return false;
    };
    if stream.write_all(line.as_bytes()).is_err() || stream.write_all(b"\n").is_err() {
        return false;
    }
    let mut buf = [0u8; 4096];
    let Ok(n) = stream.read(&mut buf) else {
        return false;
    };
    let Ok(resp) = serde_json::from_slice::<Response>(&buf[..n]) else {
        return false;
    };
    resp.result
        .and_then(|v| v.get("pong").and_then(|p| p.as_bool()))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn lock_creates_file() {
        let dir = tempdir().unwrap();
        std::env::set_var("KUMA_RUNTIME_DIR", dir.path());
        let _lock = InstanceLock::acquire().unwrap();
        assert!(dir.path().join("kuma-daemon.lock").exists());
        std::env::remove_var("KUMA_RUNTIME_DIR");
    }
}
