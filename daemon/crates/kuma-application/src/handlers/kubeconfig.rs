use crate::handlers::kuma_err::kube_err;
use kuma_protocol::jsonrpc::Response;
use kuma_store::KubeConfigStore;
use serde_json::{json, Value};

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
    let Some(kid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    let path = store.material_path(kid);
    let kube_path = if kid == kuma_store::kubeconfig::DEFAULT_ID {
        store
            .get(kid, false)
            .ok()
            .and_then(|v| {
                v.get("kubeconfig")
                    .and_then(|k| k.get("sourceFilePath"))
                    .and_then(|p| p.as_str())
                    .map(str::to_string)
            })
            .unwrap_or_default()
    } else {
        path.display().to_string()
    };
    let output = std::process::Command::new("kubectl")
        .env("KUBECONFIG", &kube_path)
        .args(["version", "--client", "-o", "json"])
        .output();
    match output {
        Ok(out) if out.status.success() => Response::ok(
            id,
            json!({
                "ok": true,
                "clientVersion": String::from_utf8_lossy(&out.stdout).trim(),
            }),
        ),
        Ok(out) => Response::ok(
            id,
            json!({
                "ok": false,
                "stderr": String::from_utf8_lossy(&out.stderr).trim(),
            }),
        ),
        Err(e) => Response::ok(id, json!({ "ok": false, "error": e.to_string() })),
    }
}
