use crate::exec_gate::{provider_locked_response, service_runtime_locked};
use crate::handlers::kuma_err::service_err;
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Response;
use kuma_store::{EventBus, ProviderStore, ServiceStore, Vault};
use serde_json::{json, Value};
use std::sync::Arc;

pub fn list(id: Option<Value>, store: &ProviderStore, params: &Value) -> Response {
    let Some(sid) = params.get("serviceID").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing serviceID");
    };
    match store.list(sid) {
        Ok(body) => Response::ok(id, body),
        Err(e) => service_err(id, e),
    }
}

pub fn add(
    id: Option<Value>,
    store: &ProviderStore,
    svc_store: &ServiceStore,
    bus: &Arc<EventBus>,
    exec: &ExecEngine,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    if let Some(sid) = obj.get("serviceID").and_then(|v| v.as_str()) {
        if service_runtime_locked(exec, sid) {
            return provider_locked_response(id);
        }
    }
    match store.add(obj) {
        Ok(body) => {
            if let Some(sid) = obj.get("serviceID").and_then(|v| v.as_str()) {
                if let Ok(svc) = svc_store.get(sid) {
                    let _ = bus.publish(
                        "service.updated",
                        json!({
                            "serviceID": sid,
                            "workspaceID": svc.get("workspaceID"),
                            "changed": ["providers", "activeProvider"],
                        }),
                    );
                }
            }
            Response::ok(id, body)
        }
        Err(e) => service_err(id, e),
    }
}

pub fn update(
    id: Option<Value>,
    store: &ProviderStore,
    vault: &Vault,
    bus: &Arc<EventBus>,
    exec: &ExecEngine,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    if let Some(pid) = obj.get("id").and_then(|v| v.as_str()) {
        if let Ok(body) = store.get(pid) {
            if let Some(sid) = body.get("serviceID").and_then(|v| v.as_str()) {
                if service_runtime_locked(exec, sid) {
                    return provider_locked_response(id);
                }
            }
        }
    }
    match store.update(vault, obj) {
        Ok(body) => {
            if let Some(sid) = body
                .get("provider")
                .and_then(|p| p.get("serviceID"))
                .and_then(|v| v.as_str())
            {
                let _ = bus.publish(
                    "service.updated",
                    json!({ "serviceID": sid, "changed": ["providers"] }),
                );
            }
            Response::ok(id, body)
        }
        Err(e) => service_err(id, e),
    }
}

pub fn delete(
    id: Option<Value>,
    store: &ProviderStore,
    bus: &Arc<EventBus>,
    exec: &ExecEngine,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    if let Some(pid) = obj.get("id").and_then(|v| v.as_str()) {
        if let Ok(body) = store.get(pid) {
            if let Some(sid) = body.get("serviceID").and_then(|v| v.as_str()) {
                if service_runtime_locked(exec, sid) {
                    return provider_locked_response(id);
                }
            }
        }
    }
    let sid = obj.get("id").and_then(|v| v.as_str()).map(str::to_string);
    match store.delete(obj) {
        Ok(body) => {
            let _ = bus.publish(
                "service.updated",
                json!({
                    "serviceID": sid,
                    "changed": ["providers", "activeProvider"],
                }),
            );
            Response::ok(id, body)
        }
        Err(e) => service_err(id, e),
    }
}

pub fn set_ports(
    id: Option<Value>,
    store: &ProviderStore,
    bus: &Arc<EventBus>,
    exec: &ExecEngine,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    if let Some(sid) = obj.get("serviceID").and_then(|v| v.as_str()) {
        if service_runtime_locked(exec, sid) {
            return provider_locked_response(id);
        }
    }
    let sid = obj.get("serviceID").cloned();
    match store.set_ports(obj) {
        Ok(body) => {
            let _ = bus.publish(
                "service.updated",
                json!({ "serviceID": sid, "changed": ["ports"] }),
            );
            Response::ok(id, body)
        }
        Err(e) => service_err(id, e),
    }
}
