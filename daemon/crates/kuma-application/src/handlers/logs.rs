use kuma_protocol::jsonrpc::Response;
use kuma_store::LogBuffer;
use serde_json::{json, Value};

pub fn tail(id: Option<Value>, logs: &LogBuffer, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let limit = params
        .get("limit")
        .and_then(|v| v.as_u64())
        .unwrap_or(100) as usize;
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

pub fn workload_tail(id: Option<Value>, logs: &LogBuffer, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let mut body = logs.tail(sid, 200);
    let spool_lines = read_workload_spool(sid);
    if let Some(obj) = body.as_object_mut() {
        obj.insert("workload".into(), json!(true));
        if !spool_lines.is_empty() {
            let lines = obj
                .entry("lines")
                .or_insert_with(|| json!([]))
                .as_array_mut();
            if let Some(arr) = lines {
                for line in spool_lines {
                    arr.push(json!({ "text": line, "source": "spool" }));
                }
            }
        }
    }
    Response::ok(id, body)
}

fn read_workload_spool(service_id: &str) -> Vec<String> {
    let path = kuma_protocol::paths::runtime_dir()
        .join("logs")
        .join(format!("{service_id}.ndjson"));
    let Ok(data) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    data.lines().map(str::to_string).collect()
}

pub fn follow(id: Option<Value>, logs: &LogBuffer, params: &Value) -> Response {
    let sid = params
        .get("serviceID")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if sid.is_empty() {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing serviceID");
    }
    Response::ok(id, logs.follow_snapshot(sid))
}
