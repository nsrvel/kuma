//! Application layer: orchestrates use cases; no Tokio, no sockets.

mod context;
mod dispatch;
mod exec_gate;
mod handlers;
pub mod lifecycle;

pub use context::{apply_client_kind, ClientKind, DispatchContext, Transport};
pub use dispatch::{Application, DispatchOutcome};
pub use lifecycle::{DataCounts, LifecycleState};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::{ClientKind, DispatchContext};
    use kuma_protocol::jsonrpc::{Request, ERR_METHOD_NOT_FOUND};
    use kuma_protocol::methods;
    use kuma_exec::ExecEngine;
    use kuma_store::StoreHandle;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    fn test_app() -> Application {
        let dir = tempfile::tempdir().unwrap();
        let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
        Application::new(
            store,
            ExecEngine::new(),
            Arc::new(|| {}),
            LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000001".into()),
            DataCounts::empty(),
        )
    }

    #[test]
    fn dt_lif_01_ping_returns_protocol_version() {
        let app = test_app();
        let req = Request {
            jsonrpc: "2.0".into(),
            method: methods::DAEMON_PING.into(),
            params: serde_json::json!({}),
            id: Some(1.into()),
        };
        let mut ctx = DispatchContext::unix(ClientKind::Cli);
        let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
            panic!("expected reply");
        };
        let result = resp.result.unwrap();
        assert_eq!(result["pong"], true);
        assert!(result.get("protocolVersion").is_some());
    }

    #[test]
    fn dt_lif_11_status_has_required_fields() {
        let app = test_app();
        let req = Request {
            jsonrpc: "2.0".into(),
            method: methods::DAEMON_STATUS.into(),
            params: serde_json::json!({}),
            id: Some(2.into()),
        };
        let mut ctx = DispatchContext::unix(ClientKind::Cli);
        let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
            panic!("expected reply");
        };
        let r = resp.result.unwrap();
        for key in [
            "version",
            "protocolVersion",
            "uptimeSecs",
            "dataDir",
            "runtimeDir",
            "socketPath",
            "dbPath",
            "daemonStatePath",
            "schemaMigrations",
            "workspaceCount",
            "serviceCount",
            "runningServices",
            "legacyAppRunning",
            "instanceId",
        ] {
            assert!(r.get(key).is_some(), "missing key {key}");
        }
    }

    #[test]
    fn unknown_method_not_found() {
        let app = test_app();
        let req = Request {
            jsonrpc: "2.0".into(),
            method: "not.a.real.method".into(),
            params: serde_json::json!({}),
            id: Some(3.into()),
        };
        let mut ctx = DispatchContext::unix(ClientKind::Cli);
        let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
            panic!("expected reply");
        };
        assert_eq!(resp.error.as_ref().unwrap().code, ERR_METHOD_NOT_FOUND);
    }

    #[test]
    fn shutdown_requests_shutdown() {
        let count = Arc::new(AtomicUsize::new(0));
        let c = Arc::clone(&count);
        let dir = tempfile::tempdir().unwrap();
        let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
        let app = Application::new(
            store,
            ExecEngine::new(),
            Arc::new(move || {
                c.fetch_add(1, Ordering::SeqCst);
            }),
            LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000002".into()),
            DataCounts::empty(),
        );
        let req = Request {
            jsonrpc: "2.0".into(),
            method: methods::DAEMON_SHUTDOWN.into(),
            params: serde_json::json!({}),
            id: Some(4.into()),
        };
        let mut ctx = DispatchContext::unix(ClientKind::Cli);
        let DispatchOutcome::ShutdownRequested(resp) = app.dispatch(req, &mut ctx) else {
            panic!("expected shutdown");
        };
        assert!(resp.result.is_some());
        assert_eq!(count.load(Ordering::SeqCst), 1);
    }
}
