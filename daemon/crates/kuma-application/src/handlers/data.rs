use kuma_protocol::jsonrpc::{Response, ERR_KUMA};
use kuma_store::{DataPort, StoreError, StoreHandle};
use serde_json::Value;
use std::sync::Arc;

fn store_err(id: Option<Value>, err: StoreError) -> Response {
    Response::err(id, ERR_KUMA, err.to_string())
}

pub fn export(id: Option<Value>, port: &DataPort) -> Response {
    match port.export() {
        Ok(v) => Response::ok(id, v),
        Err(e) => store_err(id, e),
    }
}

pub fn export_service_json(id: Option<Value>, port: &DataPort, params: &Value) -> Response {
    let sid = params
        .get("id")
        .or_else(|| params.get("serviceID"))
        .and_then(|v| v.as_str());
    let Some(sid) = sid else {
        return Response::err(id, ERR_KUMA, "missing id");
    };
    match port.export_service_json(sid) {
        Ok(v) => Response::ok(id, v),
        Err(e) => store_err(id, e),
    }
}

pub fn import_preview(id: Option<Value>, port: &DataPort, params: &Value) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, ERR_KUMA, "invalid params");
    };
    match port.import_preview(obj) {
        Ok(v) => Response::ok(id, v),
        Err(e) => store_err(id, e),
    }
}

pub fn import(
    id: Option<Value>,
    port: &DataPort,
    bus: &Arc<kuma_store::EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, ERR_KUMA, "invalid params");
    };
    match port.import(obj) {
        Ok(v) => {
            let ws_count = v.get("counts").and_then(|c| c.get("workspaces")).and_then(|n| n.as_u64()).unwrap_or(0);
            let svc_count = v.get("counts").and_then(|c| c.get("services")).and_then(|n| n.as_u64()).unwrap_or(0);
            let _ = bus.publish(
                "data.imported",
                serde_json::json!({
                    "strategy": "replace",
                    "workspaceCount": ws_count,
                    "serviceCount": svc_count,
                }),
            );
            Response::ok(id, v)
        }
        Err(e) => store_err(id, e),
    }
}

pub fn factory_reset(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<kuma_exec::ExecEngine>,
    bus: &Arc<kuma_store::EventBus>,
) -> Response {
    let ids = exec.running_service_ids();
    for sid in ids {
        let _ = kuma_exec::stop_service(exec, &sid);
        let _ = store.runtime_process().delete_row(&sid);
    }
    match store.dataport().factory_reset() {
        Ok(v) => {
            let _ = bus.publish("data.reset", serde_json::json!({}));
            Response::ok(id, v)
        }
        Err(e) => store_err(id, e),
    }
}
