use kuma_domain::SettingsError;
use kuma_protocol::jsonrpc::{Response, ERR_KUMA};
use kuma_store::SettingsStore;
use serde_json::{json, Map, Value};

pub fn settings_err(id: Option<Value>, err: SettingsError) -> Response {
    let mut data = json!({ "kumaCode": err.code() });
    if let SettingsError::PathInvalid { key, .. } = &err {
        data["details"] = json!({ "key": key });
    }
    if let SettingsError::ConflictStale { key } = &err {
        data["details"] = json!({ "key": key });
    }
    Response {
        jsonrpc: "2.0".into(),
        result: None,
        error: Some(kuma_protocol::jsonrpc::RpcError {
            code: ERR_KUMA,
            message: err.message(),
            data: Some(data),
        }),
        id,
    }
}

pub fn list(id: Option<Value>, store: &SettingsStore, params: &Value) -> Response {
    let prefix = params.get("prefix").and_then(|v| v.as_str());
    let include_client = params
        .get("includeClient")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    match store.list(prefix, include_client) {
        Ok(settings) => Response::ok(id, json!({ "settings": settings })),
        Err(e) => settings_err(id, e),
    }
}

pub fn get(id: Option<Value>, store: &SettingsStore, params: &Value) -> Response {
    let Some(key) = params.get("key").and_then(|v| v.as_str()) else {
        return Response::err(id, ERR_KUMA, "missing key");
    };
    match store.get(key) {
        Ok(setting) => Response::ok(id, setting),
        Err(e) => settings_err(id, e),
    }
}

pub fn set(id: Option<Value>, store: &SettingsStore, params: &Value) -> Response {
    let Some(values) = params.get("values").and_then(|v| v.as_object()) else {
        return Response::err(id, ERR_KUMA, "missing values object");
    };
    let strict = params
        .get("strict")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let expected = params.get("expectedUpdatedAt").and_then(|v| v.as_object());
    let map: Map<String, Value> = values.clone();
    let exp = expected.cloned();
    match store.set(&map, strict, exp.as_ref()) {
        Ok(result) => Response::ok(
            id,
            json!({
                "updated": result.updated,
                "removed": result.removed,
                "validation": result.validation,
            }),
        ),
        Err(e) => settings_err(id, e),
    }
}

pub fn reset(id: Option<Value>, store: &SettingsStore) -> Response {
    match store.reset() {
        Ok(result) => Response::ok(
            id,
            json!({
                "removed": result.removed,
                "keys": result.keys,
            }),
        ),
        Err(e) => settings_err(id, e),
    }
}
