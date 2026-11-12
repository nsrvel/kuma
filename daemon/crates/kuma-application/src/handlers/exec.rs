use crate::handlers::kuma_err::service_err;
use kuma_exec::{check_port, restart_service, start_service, stop_service, ExecEngine, ExecError};
use kuma_protocol::jsonrpc::{Response, ERR_KUMA};
use kuma_store::{EventBus, ServiceStore, StoreHandle};
use serde_json::{json, Map, Value};
use std::sync::Arc;

fn exec_err(id: Option<Value>, err: ExecError) -> Response {
    Response::err(id, ERR_KUMA, err.to_string())
}

fn active_provider(
    store: &StoreHandle,
    service_id: &str,
) -> Result<Value, kuma_domain::ServiceError> {
    let list = store.provider().list(service_id)?;
    let active = list
        .get("activeProviderID")
        .and_then(|v| v.as_str())
        .ok_or_else(|| kuma_domain::ServiceError::ProviderNotFound { id: String::new() })?;
    store.provider().get_for_exec(active, store.vault())
}

pub fn status(id: Option<Value>, exec: &Arc<ExecEngine>, params: &Value) -> Response {
    let sid = params
        .get("id")
        .or_else(|| params.get("serviceID"))
        .and_then(|v| v.as_str());
    let Some(sid) = sid else {
        return Response::err(id, ERR_KUMA, "missing id");
    };
    Response::ok(id, exec.status_json(sid))
}

pub fn statuses(id: Option<Value>, exec: &Arc<ExecEngine>, params: &Value) -> Response {
    let ids: Vec<String> = params
        .get("serviceIDs")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    Response::ok(id, exec.statuses_json(&ids))
}

pub fn ports_check(id: Option<Value>, params: &Value) -> Response {
    let port = params
        .get("localPort")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as u16;
    if port == 0 {
        return Response::err(id, ERR_KUMA, "invalid localPort");
    }
    Response::ok(id, check_port(port))
}

pub fn start(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<ExecEngine>,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let sid = params
        .get("id")
        .or_else(|| params.get("serviceID"))
        .and_then(|v| v.as_str());
    let Some(sid) = sid else {
        return Response::err(id, ERR_KUMA, "missing id");
    };
    if let Ok(svc) = store.service().get(sid) {
        if svc
            .get("isDisabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            return Response {
                jsonrpc: "2.0".into(),
                result: None,
                error: Some(kuma_protocol::jsonrpc::RpcError {
                    code: ERR_KUMA,
                    message: "Service is disabled.".into(),
                    data: Some(json!({ "kumaCode": "KUMA_EXE_SERVICE_DISABLED" })),
                }),
                id,
            };
        }
    }
    let provider = match active_provider(store, sid) {
        Ok(p) => p,
        Err(e) => return service_err(id, e),
    };
    match start_service(exec, sid, &provider) {
        Ok(()) => {
            if let Some(pid) = exec.child_pid(sid) {
                let _ = store.runtime_process().upsert_running(sid, pid);
            }
            let _ = bus.publish(
                "service.state_changed",
                json!({ "serviceID": sid, "status": "running" }),
            );
            Response::ok(id, json!({ "started": true }))
        }
        Err(e) => exec_err(id, e),
    }
}

pub fn stop(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<ExecEngine>,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let sid = params
        .get("id")
        .or_else(|| params.get("serviceID"))
        .and_then(|v| v.as_str());
    let Some(sid) = sid else {
        return Response::err(id, ERR_KUMA, "missing id");
    };
    let _ = store.runtime_process().mark_intentional_stop(sid);
    match stop_service(exec, sid) {
        Ok(()) => {
            let _ = store.runtime_process().delete_row(sid);
            let _ = bus.publish(
                "service.state_changed",
                json!({ "serviceID": sid, "status": "stopped" }),
            );
            Response::ok(id, json!({ "stopped": true }))
        }
        Err(e) => exec_err(id, e),
    }
}

pub fn restart(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<ExecEngine>,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let sid = params
        .get("id")
        .or_else(|| params.get("serviceID"))
        .and_then(|v| v.as_str());
    let Some(sid) = sid else {
        return Response::err(id, ERR_KUMA, "missing id");
    };
    if let Ok(svc) = store.service().get(sid) {
        if svc
            .get("isDisabled")
            .and_then(|v| v.as_bool())
            .unwrap_or(false)
        {
            let _ = stop_service(exec, sid);
            let _ = store.runtime_process().delete_row(sid);
            return Response {
                jsonrpc: "2.0".into(),
                result: None,
                error: Some(kuma_protocol::jsonrpc::RpcError {
                    code: ERR_KUMA,
                    message: "Service is disabled.".into(),
                    data: Some(json!({ "kumaCode": "KUMA_EXE_SERVICE_DISABLED" })),
                }),
                id,
            };
        }
    }
    let provider = match active_provider(store, sid) {
        Ok(p) => p,
        Err(e) => return service_err(id, e),
    };
    match restart_service(exec, sid, &provider) {
        Ok(()) => {
            if let Some(pid) = exec.child_pid(sid) {
                let _ = store.runtime_process().upsert_running(sid, pid);
            }
            let _ = bus.publish(
                "service.state_changed",
                json!({ "serviceID": sid, "status": "running" }),
            );
            Response::ok(id, json!({ "restarted": true }))
        }
        Err(e) => exec_err(id, e),
    }
}

pub fn start_all(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<ExecEngine>,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let empty = Map::new();
    let list = match store.service().list(params.as_object().unwrap_or(&empty)) {
        Ok(v) => v,
        Err(e) => return service_err(id, e),
    };
    let ids: Vec<String> = list
        .get("items")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter(|s| {
                    !s.get("isDisabled")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)
                })
                .filter_map(|s| s.get("id").and_then(|x| x.as_str()).map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    let mut started = 0u64;
    for sid in ids {
        let provider = match active_provider(store, &sid) {
            Ok(p) => p,
            Err(_) => continue,
        };
        if start_service(exec, &sid, &provider).is_ok() {
            let _ = bus.publish(
                "service.state_changed",
                json!({ "serviceID": sid, "status": "running" }),
            );
            started += 1;
        }
    }
    Response::ok(id, json!({ "started": started }))
}

pub fn stop_all(
    store: &StoreHandle,
    exec: &Arc<ExecEngine>,
    params: &Value,
    id: Option<Value>,
) -> Response {
    let ws_filter = params.get("workspaceID").and_then(|v| v.as_str());
    let ids = exec.running_service_ids();
    let mut stopped = 0;
    for sid in &ids {
        if let Some(wid) = ws_filter {
            if let Ok(svc) = store.service().get(sid) {
                if svc.get("workspaceID").and_then(|v| v.as_str()) != Some(wid) {
                    continue;
                }
            } else {
                continue;
            }
        }
        let _ = stop_service(exec, sid);
        let _ = store.runtime_process().delete_row(sid);
        stopped += 1;
    }
    Response::ok(id, json!({ "stopped": stopped }))
}

pub fn adopt_report(id: Option<Value>, exec: &Arc<ExecEngine>) -> Response {
    Response::ok(id, exec.adoption_report_json())
}

#[allow(dead_code)]
pub fn _service_store(_: &ServiceStore) {}
