use kuma_protocol::jsonrpc::Response;
use kuma_store::{KubeConfigStore, StoreHandle};
use serde_json::{json, Value};

fn kubeconfig_path(store: &StoreHandle, kid: &str) -> String {
    if kid == kuma_store::kubeconfig::DEFAULT_ID {
        store
            .kubeconfig()
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
        store.kubeconfig().material_path(kid).display().to_string()
    }
}

pub fn namespaces(id: Option<Value>, store: &StoreHandle, params: &Value) -> Response {
    let kid = params
        .get("kubeConfigID")
        .and_then(|v| v.as_str())
        .unwrap_or(kuma_store::kubeconfig::DEFAULT_ID);
    let path = kubeconfig_path(store, kid);
    let out = std::process::Command::new("kubectl")
        .env("KUBECONFIG", &path)
        .args(["get", "ns", "-o", "json"])
        .output();
    match out {
        Ok(o) if o.status.success() => {
            let parsed: Value =
                serde_json::from_slice(&o.stdout).unwrap_or(json!({ "items": [] }));
            Response::ok(id, json!({ "namespaces": parsed.get("items").cloned().unwrap_or(json!([])) }))
        }
        Ok(o) => Response::ok(
            id,
            json!({
                "namespaces": [],
                "error": String::from_utf8_lossy(&o.stderr).trim(),
            }),
        ),
        Err(e) => Response::ok(id, json!({ "namespaces": [], "error": e.to_string() })),
    }
}

pub fn resources(id: Option<Value>, store: &StoreHandle, params: &Value) -> Response {
    let kid = params
        .get("kubeConfigID")
        .and_then(|v| v.as_str())
        .unwrap_or(kuma_store::kubeconfig::DEFAULT_ID);
    let ns = params
        .get("namespace")
        .and_then(|v| v.as_str())
        .unwrap_or("default");
    let path = kubeconfig_path(store, kid);
    let out = std::process::Command::new("kubectl")
        .env("KUBECONFIG", &path)
        .args(["get", "all", "-n", ns, "-o", "json"])
        .output();
    match out {
        Ok(o) if o.status.success() => Response::ok(
            id,
            json!({ "resources": serde_json::from_slice::<Value>(&o.stdout).unwrap_or(json!({})) }),
        ),
        Ok(o) => Response::ok(
            id,
            json!({ "resources": {}, "error": String::from_utf8_lossy(&o.stderr).trim() }),
        ),
        Err(e) => Response::ok(id, json!({ "resources": {}, "error": e.to_string() })),
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
        .unwrap_or(false);
    Response::ok(
        id,
        json!({
            "resolvedTarget": if target.is_empty() { Value::Null } else { json!(target) },
            "usePattern": pattern,
            "liveTarget": Value::Null,
            "matched": !target.is_empty(),
        }),
    )
}
