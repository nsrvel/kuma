use crate::handlers::kuma_err::service_err;
use kuma_protocol::jsonrpc::Response;
use kuma_store::{EventBus, ServiceStore, StoreHandle};
use serde_json::{json, Value};
use std::sync::Arc;

fn emit_service_updated(bus: &Arc<EventBus>, service: &Value, changed: &[&str]) {
    if let (Some(sid), Some(wid)) = (
        service.get("id").and_then(|v| v.as_str()),
        service.get("workspaceID").and_then(|v| v.as_str()),
    ) {
        let _ = bus.publish(
            "service.updated",
            json!({
                "serviceID": sid,
                "workspaceID": wid,
                "changed": changed,
            }),
        );
    }
}

fn emit_service_created(bus: &Arc<EventBus>, service: &Value) {
    if let (Some(sid), Some(wid)) = (
        service.get("id").and_then(|v| v.as_str()),
        service.get("workspaceID").and_then(|v| v.as_str()),
    ) {
        let _ = bus.publish(
            "service.created",
            json!({ "serviceID": sid, "workspaceID": wid }),
        );
    }
}

pub fn list(id: Option<Value>, store: &ServiceStore, params: &Value) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.list(obj) {
        Ok(body) => Response::ok(id, body),
        Err(e) => service_err(id, e),
    }
}

pub fn get(id: Option<Value>, store: &ServiceStore, params: &Value) -> Response {
    let Some(sid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    match store.get(sid) {
        Ok(service) => Response::ok(id, json!({ "service": service })),
        Err(e) => service_err(id, e),
    }
}

pub fn create(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.create(obj) {
        Ok(service) => {
            emit_service_created(bus, &service);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn update(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.update(obj) {
        Ok(service) => {
            emit_service_updated(bus, &service, &["service"]);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn delete(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(sid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    let workspace_id = store.get(sid).ok().and_then(|s| {
        s.get("workspaceID")
            .and_then(|v| v.as_str())
            .map(str::to_string)
    });
    match store.delete(sid) {
        Ok(result) => {
            let _ = bus.publish(
                "service.deleted",
                json!({ "serviceID": sid, "workspaceID": workspace_id }),
            );
            Response::ok(id, result)
        }
        Err(e) => service_err(id, e),
    }
}

pub fn duplicate(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.duplicate(obj) {
        Ok(service) => {
            emit_service_created(bus, &service);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn set_starred(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.set_starred(obj) {
        Ok(service) => {
            emit_service_updated(bus, &service, &["service"]);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn set_disabled(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.set_disabled(obj) {
        Ok(service) => {
            emit_service_updated(bus, &service, &["service"]);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn set_groups(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.set_groups(obj) {
        Ok(service) => {
            emit_service_updated(bus, &service, &["memberships"]);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn toggle_group(
    id: Option<Value>,
    store: &ServiceStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.toggle_group(obj) {
        Ok(service) => {
            emit_service_updated(bus, &service, &["memberships"]);
            Response::ok(id, json!({ "service": service }))
        }
        Err(e) => service_err(id, e),
    }
}

pub fn switch_provider(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<kuma_exec::ExecEngine>,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    let sid = obj.get("id").and_then(|v| v.as_str()).unwrap_or("");
    let was_running = exec.snapshot(sid).status == "running";
    if was_running {
        let _ = kuma_exec::stop_service(exec, sid);
    }
    match store.service().switch_provider(obj) {
        Ok(mut body) => {
            let mut restart = json!({ "attempted": was_running, "started": false });
            if was_running && body.get("changed").and_then(|v| v.as_bool()) == Some(true) {
                if let Ok(provider) = active_provider_for_switch(store, sid) {
                    if kuma_exec::start_service(exec, sid, &provider).is_ok() {
                        restart["started"] = true.into();
                    }
                }
            }
            if let Some(obj) = body.as_object_mut() {
                obj.insert("restart".to_string(), restart);
            }
            if body.get("changed").and_then(|v| v.as_bool()) == Some(true) {
                if let Some(svc) = body.get("service") {
                    emit_service_updated(bus, svc, &["activeProvider"]);
                }
            }
            Response::ok(id, body)
        }
        Err(e) => service_err(id, e),
    }
}

fn active_provider_for_switch(
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

pub fn preflight(id: Option<Value>, store: &ServiceStore, params: &Value) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(
            id,
            kuma_protocol::jsonrpc::ERR_KUMA,
            "expected object params",
        );
    };
    match store.preflight(obj) {
        Ok(body) => Response::ok(id, body),
        Err(e) => service_err(id, e),
    }
}
