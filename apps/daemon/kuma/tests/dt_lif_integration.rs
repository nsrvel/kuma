//! DT-LIF integration tests (subprocess + real `kuma` binary).

use kuma_client::DaemonClient;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;
use tempfile::TempDir;

fn kuma_bin() -> PathBuf {
    PathBuf::from(env!("CARGO_BIN_EXE_kuma"))
}

fn spawn_daemon(dir: &TempDir) -> std::process::Child {
    Command::new(kuma_bin())
        .args(["daemon", "run"])
        .env("KUMA_RUNTIME_DIR", dir.path())
        .env("KUMA_DATA_DIR", dir.path())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn daemon")
}

async fn wait_for_socket(dir: &TempDir) {
    let socket = dir.path().join("kuma-daemon.sock");
    for _ in 0..100 {
        if socket.exists() && DaemonClient::connect_socket(&socket).await.is_ok() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("daemon socket not ready");
}

fn stop_daemon(mut child: std::process::Child) {
    let _ = child.kill();
    let _ = child.wait();
}

#[tokio::test]
async fn dt_lif_01_ping_via_client() {
    let dir = tempfile::tempdir().unwrap();
    let child = spawn_daemon(&dir);
    wait_for_socket(&dir).await;

    let socket = dir.path().join("kuma-daemon.sock");
    let mut client = DaemonClient::connect_socket(&socket).await.unwrap();
    let pong = client.ping().await.unwrap();
    assert_eq!(pong["pong"], true);

    stop_daemon(child);
}

#[tokio::test]
async fn dt_lif_02_second_daemon_exits_nonzero() {
    let dir = tempfile::tempdir().unwrap();
    let child = spawn_daemon(&dir);
    wait_for_socket(&dir).await;

    let output = Command::new(kuma_bin())
        .args(["daemon", "run"])
        .env("KUMA_RUNTIME_DIR", dir.path())
        .env("KUMA_DATA_DIR", dir.path())
        .output()
        .unwrap();
    assert!(
        !output.status.success(),
        "second daemon should fail: stderr={}",
        String::from_utf8_lossy(&output.stderr)
    );

    let socket = dir.path().join("kuma-daemon.sock");
    let mut client = DaemonClient::connect_socket(&socket).await.unwrap();
    assert!(client.ping().await.unwrap()["pong"].as_bool().unwrap());

    stop_daemon(child);
}

#[tokio::test]
async fn dt_lif_03_stale_socket_removed_then_starts() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir.path()).unwrap();
    let socket = dir.path().join("kuma-daemon.sock");
    std::fs::write(&socket, b"stale").unwrap();

    let child = spawn_daemon(&dir);
    wait_for_socket(&dir).await;

    let mut client = DaemonClient::connect_socket(&socket).await.unwrap();
    let status = client.status().await.unwrap();
    assert!(status.get("uptimeSecs").is_some());

    stop_daemon(child);
}

#[tokio::test]
async fn dt_lif_11_status_fields_present() {
    let dir = tempfile::tempdir().unwrap();
    let child = spawn_daemon(&dir);
    wait_for_socket(&dir).await;

    let mut client = DaemonClient::connect_socket(dir.path().join("kuma-daemon.sock"))
        .await
        .unwrap();
    let r = client.status().await.unwrap();
    assert_eq!(r["schemaMigrations"].as_array().unwrap().len(), 8);
    assert!(r["workspaceCount"].as_u64().unwrap() >= 1);
    for key in [
        "version",
        "protocolVersion",
        "uptimeSecs",
        "dataDir",
        "runtimeDir",
        "socketPath",
        "instanceId",
    ] {
        assert!(r.get(key).is_some(), "missing {key}");
    }

    stop_daemon(child);
}
