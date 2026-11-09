use crate::handlers::kuma_err::kube_err;
use kuma_protocol::jsonrpc::Response;
use kuma_store::KubeConfigStore;
use serde_json::Value;

pub fn list(id: Option<Value>, store: &KubeConfigStore) -> Response {
    match store.list() {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn get(id: Option<Value>, store: &KubeConfigStore, params: &Value) -> Response {
    let Some(kid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    let reveal = params
        .get("revealSecrets")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    match store.get(kid, reveal) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn create(id: Option<Value>, store: &KubeConfigStore, params: &Value) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "invalid params");
    };
    match store.create(obj) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn update(id: Option<Value>, store: &KubeConfigStore, params: &Value) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "invalid params");
    };
    match store.update(obj) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn delete(id: Option<Value>, store: &KubeConfigStore, params: &Value) -> Response {
    let Some(kid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    match store.delete(kid) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn contexts(id: Option<Value>, store: &KubeConfigStore, params: &Value) -> Response {
    let Some(kid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    match store.contexts(kid) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn test_connection(id: Option<Value>, store: &KubeConfigStore, params: &Value) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "invalid params");
    };
    match store.test_connection(obj) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}
