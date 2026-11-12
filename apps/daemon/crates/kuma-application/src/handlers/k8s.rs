use crate::handlers::kuma_err::kube_err;
use kuma_protocol::jsonrpc::Response;
use kuma_store::{KubeConfigStore, StoreHandle};
use serde_json::Value;
use std::path::Path;

pub fn namespaces(id: Option<Value>, store: &StoreHandle, params: &Value) -> Response {
    let bin = resolve_kubectl(store);
    match store.kubeconfig().list_namespaces(params, bin.as_deref()) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn resources(id: Option<Value>, store: &StoreHandle, params: &Value) -> Response {
    let bin = resolve_kubectl(store);
    match store.kubeconfig().list_resources(params, bin.as_deref()) {
        Ok(v) => Response::ok(id, v),
        Err(e) => kube_err(id, e),
    }
}

pub fn resolve_target(id: Option<Value>, _store: &KubeConfigStore, params: &Value) -> Response {
    let target = params
        .get("targetName")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let pattern = params
        .get("usePattern")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    Response::ok(id, kuma_store::resolve_k8s_target(target, pattern))
}

/// `KUMA_KUBECTL_BIN` wins for fixtures. Otherwise settings custom path, then PATH.
fn resolve_kubectl(store: &StoreHandle) -> Option<String> {
    if let Ok(bin) = std::env::var("KUMA_KUBECTL_BIN") {
        let trimmed = bin.trim();
        if !trimmed.is_empty() {
            return is_executable_file(trimmed).then(|| trimmed.to_string());
        }
    }
    let resolved = store.env().resolve("kubectl", None, true);
    resolved
        .get("path")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn is_executable_file(path: &str) -> bool {
    let path = Path::new(path);
    std::fs::metadata(path)
        .map(|meta| {
            if meta.is_dir() {
                return false;
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                meta.permissions().mode() & 0o111 != 0
            }
            #[cfg(not(unix))]
            {
                true
            }
        })
        .unwrap_or(false)
}
