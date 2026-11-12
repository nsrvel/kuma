use crate::context::ClientKind;
use crate::lifecycle::{DataCounts, LifecycleState};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Response;
use kuma_protocol::{paths, PROTOCOL_VERSION};
use serde_json::{json, Value};
use std::sync::Arc;

pub fn ping(id: Option<Value>, client_kind: ClientKind) -> Response {
    Response::ok(
        id,
        json!({
            "pong": true,
            "protocolVersion": PROTOCOL_VERSION,
            "clientKind": client_kind.as_str(),
        }),
    )
}

pub fn status(
    id: Option<Value>,
    lifecycle: &LifecycleState,
    counts: &DataCounts,
    exec: &ExecEngine,
) -> Response {
    let running: Vec<_> = exec
        .running_service_ids()
        .into_iter()
        .map(Value::String)
        .collect();
    let data_dir = paths::data_dir();
    let runtime_dir = paths::runtime_dir();
    Response::ok(
        id,
        json!({
            "version": lifecycle.daemon_version,
            "protocolVersion": PROTOCOL_VERSION,
            "uptimeSecs": lifecycle.uptime_secs(),
            "dataDir": data_dir.display().to_string(),
            "runtimeDir": runtime_dir.display().to_string(),
            "socketPath": paths::socket_path().display().to_string(),
            "dbPath": data_dir.join("kuma.sqlite").display().to_string(),
            "daemonStatePath": data_dir.join("daemon-state.sqlite").display().to_string(),
            "schemaMigrations": counts.schema_migrations,
            "workspaceCount": counts.workspace_count,
            "serviceCount": counts.service_count,
            "runningServices": running,
            "legacyAppRunning": false,
            "adoptReport": {
                "adopted": exec.adopted_count(),
                "released": exec.released_count(),
            },
            "restListenAddr": rest_listen_addr(),
            "instanceId": lifecycle.instance_id,
        }),
    )
}

pub fn shutdown(
    id: Option<Value>,
    exec: &ExecEngine,
    bus: &Arc<kuma_store::EventBus>,
    params: &Value,
    request_shutdown: &dyn Fn(),
) -> Response {
    let stop_services = params
        .get("stopServices")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let mut stopped = 0;
    if stop_services {
        stopped = exec.stop_all();
    }
    let _ = bus.publish(
        "daemon.shutting_down",
        json!({ "stopServices": stop_services }),
    );
    request_shutdown();
    Response::ok(id, json!({ "accepted": true, "stoppedServices": stopped }))
}

fn rest_listen_addr() -> Value {
    if std::env::var("KUMA_REST").ok().as_deref() == Some("1") {
        json!("127.0.0.1:9364")
    } else {
        Value::Null
    }
}

pub fn rotate_api_token(id: Option<Value>, data_dir: &std::path::Path) -> Response {
    match kuma_store::rotate_api_token(data_dir) {
        Ok(v) => Response::ok(id, v),
        Err(e) => Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, e.to_string()),
    }
}
