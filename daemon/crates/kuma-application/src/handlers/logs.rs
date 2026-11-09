use kuma_protocol::jsonrpc::Response;
use kuma_store::{LogBuffer, StoreHandle};
use serde_json::{json, Value};

pub fn tail(id: Option<Value>, logs: &LogBuffer, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let limit = params.get("limit").and_then(|v| v.as_u64()).unwrap_or(100) as usize;
    if sid.is_empty() {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing serviceID");
    }
    Response::ok(id, logs.tail(sid, limit))
}

pub fn clear(id: Option<Value>, logs: &LogBuffer, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if sid.is_empty() {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing serviceID");
    }
    Response::ok(id, logs.clear(sid))
}

pub fn workload_tail(id: Option<Value>, store: &StoreHandle, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .or_else(|| params.get("id"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if sid.is_empty() {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing serviceID");
    }
    let limit = params
        .get("maxLines")
        .or_else(|| params.get("limit"))
        .and_then(|v| v.as_u64())
        .unwrap_or(200) as usize;
    let logs = store.logs();
    let mut text = String::new();
    let truncated = false;
    if let Ok(out) = try_kubectl_logs_tail(store, sid, limit) {
        text = out;
    } else if let Some(spool) = read_exec_spool(sid, limit) {
        text = spool;
    } else {
        let body = logs.tail(sid, limit);
        if let Some(lines) = body.get("lines").and_then(|v| v.as_array()) {
            for line in lines {
                if let Some(s) = line.as_str() {
                    text.push_str(s);
                    text.push('\n');
                } else if let Some(t) = line.get("text").and_then(|v| v.as_str()) {
                    text.push_str(t);
                    text.push('\n');
                }
            }
        }
    }
    Response::ok(
        id,
        json!({
            "serviceID": sid,
            "text": text,
            "truncated": truncated,
            "workload": true,
        }),
    )
}

fn read_exec_spool(service_id: &str, limit: usize) -> Option<String> {
    let path = kuma_protocol::paths::runtime_dir()
        .join("spool")
        .join(format!("{}.out", service_id.to_uppercase()));
    let data = std::fs::read_to_string(path).ok()?;
    let lines: Vec<&str> = data.lines().collect();
    let start = lines.len().saturating_sub(limit.max(1));
    Some(
        lines
            .iter()
            .skip(start)
            .copied()
            .collect::<Vec<_>>()
            .join("\n"),
    )
}

fn try_kubectl_logs_tail(
    store: &StoreHandle,
    service_id: &str,
    limit: usize,
) -> Result<String, ()> {
    let svc = store.service().get(service_id).map_err(|_| ())?;
    let active = svc
        .get("activeProviderID")
        .and_then(|v| v.as_str())
        .ok_or(())?;
    let plist = store.provider().list(service_id).map_err(|_| ())?;
    let provider = plist
        .get("providers")
        .and_then(|v| v.as_array())
        .and_then(|a| {
            a.iter()
                .find(|p| p.get("id").and_then(|v| v.as_str()) == Some(active))
        })
        .ok_or(())?;
    if provider.get("type").and_then(|v| v.as_str()) != Some("kubernetes") {
        return Err(());
    }
    let target = provider
        .get("targetName")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or(())?;
    let ns = provider
        .get("kubeNamespace")
        .and_then(|v| v.as_str())
        .unwrap_or("default");
    let kid = provider
        .get("kubeConfigID")
        .and_then(|v| v.as_str())
        .unwrap_or(kuma_store::kubeconfig::DEFAULT_ID);
    let kube_path = store.kubeconfig().material_path(kid);
    let kubectl = std::env::var("KUMA_KUBECTL_BIN").unwrap_or_else(|_| "kubectl".into());
    let out = std::process::Command::new(kubectl)
        .env("KUBECONFIG", kube_path)
        .args(["logs", target, "-n", ns, "--tail", &limit.to_string()])
        .output()
        .map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

pub fn follow(id: Option<Value>, logs: &LogBuffer, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if sid.is_empty() {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing serviceID");
    }
    Response::ok(id, logs.start_follow(sid))
}
