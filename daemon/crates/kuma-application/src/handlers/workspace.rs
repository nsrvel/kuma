use crate::handlers::kuma_err::workspace_err;
use kuma_protocol::jsonrpc::Response;
use kuma_store::{EventBus, StoreHandle, WorkspaceStore};
use serde_json::{json, Value};
use std::sync::Arc;

pub fn list(id: Option<Value>, store: &WorkspaceStore) -> Response {
    match store.list() {
        Ok(workspaces) => Response::ok(id, json!({ "workspaces": workspaces })),
        Err(e) => workspace_err(id, e),
    }
}

pub fn get(id: Option<Value>, store: &WorkspaceStore, params: &Value) -> Response {
    let Some(wid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    match store.get(wid) {
        Ok(ws) => Response::ok(id, json!({ "workspace": ws })),
        Err(e) => workspace_err(id, e),
    }
}

pub fn create(
    id: Option<Value>,
    store: &WorkspaceStore,
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
        Ok(ws) => {
            if let Some(wid) = ws.get("id").and_then(|v| v.as_str()) {
                let _ = bus.publish(
                    "workspace.changed",
                    json!({ "workspaceID": wid, "change": "created" }),
                );
            }
            Response::ok(id, json!({ "workspace": ws }))
        }
        Err(e) => workspace_err(id, e),
    }
}

pub fn update(
    id: Option<Value>,
    store: &WorkspaceStore,
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
        Ok(ws) => {
            if let Some(wid) = ws.get("id").and_then(|v| v.as_str()) {
                let mut payload = json!({ "workspaceID": wid, "change": "updated" });
                if obj.contains_key("imageBase64") || obj.contains_key("clearImage") {
                    payload["changed"] = json!(["image"]);
                }
                let _ = bus.publish("workspace.changed", payload);
            }
            Response::ok(id, json!({ "workspace": ws }))
        }
        Err(e) => workspace_err(id, e),
    }
}

pub fn delete(
    id: Option<Value>,
    store: &StoreHandle,
    exec: &Arc<kuma_exec::ExecEngine>,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(wid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    let list = store
        .service()
        .list(&serde_json::Map::from_iter([(
            "workspaceID".into(),
            serde_json::Value::String(wid.to_string()),
        )]))
        .ok();
    if let Some(list) = list {
        if let Some(items) = list.get("items").and_then(|v| v.as_array()) {
            for item in items {
                if let Some(sid) = item.get("id").and_then(|v| v.as_str()) {
                    let _ = kuma_exec::stop_service(exec, sid);
                }
            }
        }
    }
    match store.workspace().delete(wid) {
        Ok(result) => {
            let _ = bus.publish(
                "workspace.changed",
                json!({
                    "workspaceID": wid,
                    "change": "deleted",
                    "nextWorkspaceId": result.get("nextWorkspaceId"),
                }),
            );
            Response::ok(id, result)
        }
        Err(e) => workspace_err(id, e),
    }
}

pub fn reorder(
    id: Option<Value>,
    store: &WorkspaceStore,
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
    match store.reorder(obj) {
        Ok(workspaces) => {
            let _ = bus.publish("workspace.changed", json!({ "change": "reordered" }));
            Response::ok(id, json!({ "workspaces": workspaces }))
        }
        Err(e) => workspace_err(id, e),
    }
}

pub fn set_image(
    id: Option<Value>,
    store: &WorkspaceStore,
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
    match store.set_image(obj) {
        Ok(ws) => {
            if let Some(wid) = ws.get("id").and_then(|v| v.as_str()) {
                let _ = bus.publish(
                    "workspace.changed",
                    json!({ "workspaceID": wid, "change": "updated", "changed": ["image"] }),
                );
            }
            Response::ok(id, json!({ "workspace": ws }))
        }
        Err(e) => workspace_err(id, e),
    }
}

pub fn clear_image(
    id: Option<Value>,
    store: &WorkspaceStore,
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
    match store.clear_image(obj) {
        Ok(ws) => {
            if let Some(wid) = ws.get("id").and_then(|v| v.as_str()) {
                let _ = bus.publish(
                    "workspace.changed",
                    json!({ "workspaceID": wid, "change": "updated", "changed": ["image"] }),
                );
            }
            Response::ok(id, json!({ "workspace": ws }))
        }
        Err(e) => workspace_err(id, e),
    }
}

pub fn get_image(id: Option<Value>, store: &WorkspaceStore, params: &Value) -> Response {
    let Some(wid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    match store.get_image(wid) {
        Ok(body) => Response::ok(id, body),
        Err(e) => workspace_err(id, e),
    }
}
