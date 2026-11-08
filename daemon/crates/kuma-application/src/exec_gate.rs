use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::{Response, ERR_KUMA};

pub fn service_runtime_locked(exec: &ExecEngine, service_id: &str) -> bool {
    matches!(
        exec.snapshot(service_id).status.as_str(),
        "running" | "starting" | "reconnecting"
    )
}

pub fn provider_locked_response(id: Option<serde_json::Value>) -> Response {
    Response::err(
        id,
        ERR_KUMA,
        "Settings are read-only while active.",
    )
}
