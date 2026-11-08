mod connection;
mod instance;
mod peer;
mod rest;
pub mod rest_registry;

use anyhow::{Context, Result};
use kuma_application::{Application, DataCounts, DispatchOutcome, LifecycleState};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::{self, Response, ERR_PARSE};
use kuma_protocol::paths;
use kuma_store::StoreHandle;
use std::os::unix::io::AsRawFd;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::signal;
use tokio::sync::broadcast;
use tracing::{info, warn};

pub async fn run() -> Result<()> {
    paths::ensure_runtime_dir().context("create runtime directory")?;
    let _lock = instance::InstanceLock::acquire().context("single-instance lock")?;
    instance::prepare_stale_socket().context("prepare socket path")?;

    let store = Arc::new(
        StoreHandle::open(&paths::data_dir()).map_err(|e| anyhow::anyhow!("{}: {}", e.code(), e))?,
    );
    let counts = DataCounts {
        workspace_count: store.workspace_count().map_err(store_err)?,
        service_count: store.service_count().map_err(store_err)?,
        schema_migrations: store.schema_migrations().to_vec(),
    };
    let lifecycle = LifecycleState::new(
        env!("CARGO_PKG_VERSION"),
        store.instance_id().to_string(),
    );

    let socket = paths::socket_path();
    let listener = UnixListener::bind(&socket).context("bind unix socket")?;
    paths::set_path_mode(&socket, 0o600).context("chmod socket")?;
    info!(path = %socket.display(), "kuma daemon listening");

    let (shutdown_tx, _) = broadcast::channel::<()>(1);
    let exec = ExecEngine::new();
    {
        let store_logs = Arc::clone(&store);
        exec.set_log_sink(Arc::new(move |sid, line| {
            store_logs.logs().append(sid, line);
        }));
    }
    let app = Arc::new(Application::new(
        Arc::clone(&store),
        exec,
        {
            let shutdown_tx = shutdown_tx.clone();
            Arc::new(move || {
                let _ = shutdown_tx.send(());
            })
        },
        lifecycle,
        counts,
    ));

    let rest_app = Arc::clone(&app);
    let rest_dir = store.data_dir().to_path_buf();
    tokio::spawn(async move {
        if let Err(e) = rest::serve(rest_app, &rest_dir).await {
            tracing::warn!("REST server exited: {e}");
        }
    });

    let mut shutdown_rx = shutdown_tx.subscribe();

    let shutdown_signal = shutdown_tx.clone();
    tokio::spawn(async move {
        let _ = signal::ctrl_c().await;
        let _ = shutdown_signal.send(());
    });

    loop {
        tokio::select! {
            accept = listener.accept() => {
                let (stream, _) = accept.context("accept connection")?;
                let app = Arc::clone(&app);
                let shutdown_tx_conn = shutdown_tx.clone();
                let mut conn_shutdown = shutdown_tx.subscribe();
                tokio::spawn(async move {
                    if let Err(err) =
                        handle_connection(stream, app, shutdown_tx_conn, &mut conn_shutdown).await
                    {
                        warn!(%err, "connection ended with error");
                    }
                });
            }
            _ = shutdown_rx.recv() => {
                info!("shutting down");
                break;
            }
        }
    }

    drop(listener);
    let _ = std::fs::remove_file(&socket);
    Ok(())
}

fn store_err(e: kuma_store::StoreError) -> anyhow::Error {
    anyhow::anyhow!("{}: {}", e.code(), e)
}

async fn handle_connection(
    stream: UnixStream,
    app: Arc<Application>,
    shutdown_tx: broadcast::Sender<()>,
    shutdown: &mut broadcast::Receiver<()>,
) -> Result<()> {
    if !peer::peer_uid_matches_daemon(stream.as_raw_fd())? {
        warn!("rejected connection: peer uid mismatch");
        return Ok(());
    }

    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    loop {
        tokio::select! {
            line = lines.next_line() => {
                let Some(line) = line.context("read line")? else { break };
                if line.trim().is_empty() {
                    continue;
                }
                if line.len() > kuma_protocol::MAX_NDJSON_LINE_BYTES {
                    let resp = Response::err(None, ERR_PARSE, "parse error");
                    writer.write_all(resp.to_line()?.as_bytes()).await?;
                    continue;
                }

                let response = match jsonrpc::Request::parse_line(&line) {
                    Ok(req) => {
                        tracing::debug!(method = %req.method, id = ?req.id, "rpc request");
                        match app.dispatch(req) {
                            DispatchOutcome::Reply(r) => r,
                            DispatchOutcome::ShutdownRequested(r) => {
                                let _ = shutdown_tx.send(());
                                r
                            }
                        }
                    }
                    Err(_) => Response::err(None, ERR_PARSE, "parse error"),
                };
                writer.write_all(response.to_line()?.as_bytes()).await?;
            }
            _ = shutdown.recv() => break,
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use kuma_application::{Application, DataCounts, DispatchOutcome, LifecycleState};
    use kuma_protocol::jsonrpc::Request;
    use kuma_protocol::methods;
    use std::sync::Arc;
    use std::time::Duration;
    use tempfile::tempdir;
    use tokio::sync::Mutex;

    static DAEMON_ITEST: Mutex<()> = Mutex::const_new(());

    async fn connect_when_ready(dir: &tempfile::TempDir) -> kuma_client::DaemonClient {
        let socket = dir.path().join("kuma-daemon.sock");
        for _ in 0..100 {
            if let Ok(client) = kuma_client::DaemonClient::connect_socket(&socket).await {
                return client;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        panic!("daemon socket not ready");
    }

    #[tokio::test]
    async fn integration_ping_over_socket() {
        let _guard = DAEMON_ITEST.lock().await;
        let dir = tempdir().unwrap();
        let data_dir = dir.path().to_path_buf();
        let runtime_dir = dir.path().to_path_buf();

        let server = tokio::spawn(async move {
            std::env::set_var("KUMA_RUNTIME_DIR", &runtime_dir);
            std::env::set_var("KUMA_DATA_DIR", &data_dir);
            let _ = run().await;
        });

        let mut client = connect_when_ready(&dir).await;
        let result = client.ping().await.unwrap();
        assert_eq!(result["pong"], true);

        server.abort();
    }

    #[tokio::test]
    async fn integration_status_over_client() {
        let _guard = DAEMON_ITEST.lock().await;
        let dir = tempdir().unwrap();
        let data_dir = dir.path().to_path_buf();
        let runtime_dir = dir.path().to_path_buf();

        let server = tokio::spawn(async move {
            std::env::set_var("KUMA_RUNTIME_DIR", &runtime_dir);
            std::env::set_var("KUMA_DATA_DIR", &data_dir);
            let _ = run().await;
        });

        let mut client = connect_when_ready(&dir).await;
        let status = client.status().await.unwrap();
        assert!(status.get("instanceId").is_some());
        assert_eq!(status["workspaceCount"].as_u64().unwrap(), 1);
        assert_eq!(status["schemaMigrations"].as_array().unwrap().len(), 8);

        server.abort();
    }

    #[tokio::test]
    async fn integration_workspace_list_over_socket() {
        let _guard = DAEMON_ITEST.lock().await;
        let dir = tempdir().unwrap();
        let data_dir = dir.path().to_path_buf();
        let runtime_dir = dir.path().to_path_buf();
        let missing = dir.path().join("no-legacy.plist");
        std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", missing.to_str().unwrap());

        let server = tokio::spawn(async move {
            std::env::set_var("KUMA_RUNTIME_DIR", &runtime_dir);
            std::env::set_var("KUMA_DATA_DIR", &data_dir);
            let _ = run().await;
        });

        let mut client = connect_when_ready(&dir).await;
        let result = client
            .call(kuma_protocol::methods::WORKSPACE_LIST, serde_json::json!({}))
            .await
            .unwrap();
        assert_eq!(result["workspaces"].as_array().unwrap().len(), 1);

        std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
        server.abort();
    }

    #[tokio::test]
    async fn integration_settings_list_over_socket() {
        let _guard = DAEMON_ITEST.lock().await;
        let dir = tempdir().unwrap();
        let data_dir = dir.path().to_path_buf();
        let runtime_dir = dir.path().to_path_buf();
        let missing = dir.path().join("no-legacy.plist");
        std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", missing.to_str().unwrap());

        let server = tokio::spawn(async move {
            std::env::set_var("KUMA_RUNTIME_DIR", &runtime_dir);
            std::env::set_var("KUMA_DATA_DIR", &data_dir);
            let _ = run().await;
        });

        let mut client = connect_when_ready(&dir).await;
        let result = client
            .call(
                kuma_protocol::methods::SETTINGS_LIST,
                serde_json::json!({ "includeClient": false }),
            )
            .await
            .unwrap();
        assert_eq!(result["settings"].as_array().unwrap().len(), 26);

        std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
        server.abort();
    }

    #[test]
    fn dispatch_ping_unit() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("no-legacy.plist");
        std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", missing.to_str().unwrap());
        let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
        std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
        let app = Application::new(
            store,
            ExecEngine::new(),
            Arc::new(|| {}),
            LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000003".into()),
            DataCounts::empty(),
        );
        let req = Request {
            jsonrpc: "2.0".into(),
            method: methods::DAEMON_PING.into(),
            params: serde_json::json!({}),
            id: Some(1.into()),
        };
        let DispatchOutcome::Reply(resp) = app.dispatch(req) else {
            panic!("reply");
        };
        assert!(resp.result.is_some());
    }
}
