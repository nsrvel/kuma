use crate::handlers::settings::settings_err;
use kuma_domain::SettingsError;
use kuma_protocol::jsonrpc::Response;
use kuma_store::EnvService;
use serde_json::Value;

pub fn path(id: Option<Value>, env: &EnvService, params: &Value) -> Response {
    let refresh = params.get("refresh").and_then(|v| v.as_bool()).unwrap_or(false);
    Response::ok(id, env.path_json(refresh))
}

pub fn refresh(id: Option<Value>, env: &EnvService) -> Response {
    Response::ok(id, env.refresh())
}

pub fn resolve_executable(id: Option<Value>, env: &EnvService, params: &Value) -> Response {
    let Some(command) = params.get("command").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing command");
    };
    let custom = params.get("customPath").and_then(|v| v.as_str());
    let apply = params
        .get("applySettings")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    Response::ok(id, env.resolve(command, custom, apply))
}

pub fn validate_binary(id: Option<Value>, env: &EnvService, params: &Value) -> Response {
    let path = params.get("path").and_then(|v| v.as_str()).unwrap_or("");
    let expected = params.get("expected").and_then(|v| v.as_str()).unwrap_or("");
    Response::ok(id, env.validate(path, expected))
}

pub fn dependencies(id: Option<Value>, env: &EnvService) -> Response {
    Response::ok(id, env.dependencies())
}

/// Env handlers do not surface SettingsError today; kept for symmetry with settings module.
#[allow(dead_code)]
pub fn map_settings(err: SettingsError) -> Response {
    settings_err(None, err)
}
