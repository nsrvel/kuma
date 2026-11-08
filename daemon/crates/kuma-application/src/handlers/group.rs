use crate::handlers::kuma_err::group_err;
use kuma_protocol::jsonrpc::Response;
use kuma_store::{EventBus, GroupStore};
use serde_json::{json, Value};
use std::sync::Arc;

pub fn list(id: Option<Value>, store: &GroupStore, params: &Value) -> Response {
    let Some(wid) = params.get("workspaceID").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing workspaceID");
    };
    match store.list(wid) {
        Ok(groups) => Response::ok(id, json!({ "groups": groups })),
        Err(e) => group_err(id, e),
    }
}

pub fn create(
    id: Option<Value>,
    store: &GroupStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "expected object params");
    };
    match store.create(obj) {
        Ok(group) => {
            let ws = group.get("workspaceID").cloned();
            let gid = group.get("id").and_then(|v| v.as_str());
            let _ = bus.publish(
                "group.changed",
                json!({
                    "workspaceID": ws,
                    "groupID": gid,
                    "change": "created",
                }),
            );
            Response::ok(id, json!({ "group": group }))
        }
        Err(e) => group_err(id, e),
    }
}

pub fn update(
    id: Option<Value>,
    store: &GroupStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "expected object params");
    };
    match store.update(obj) {
        Ok(group) => {
            let _ = bus.publish(
                "group.changed",
                json!({
                    "workspaceID": group.get("workspaceID"),
                    "groupID": group.get("id"),
                    "change": "updated",
                }),
            );
            Response::ok(id, json!({ "group": group }))
        }
        Err(e) => group_err(id, e),
    }
}

pub fn delete(
    id: Option<Value>,
    store: &GroupStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(gid) = params.get("id").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing id");
    };
    match store.delete(gid) {
        Ok(result) => {
            let _ = bus.publish(
                "group.changed",
                json!({ "groupID": gid, "change": "deleted" }),
            );
            Response::ok(id, result)
        }
        Err(e) => group_err(id, e),
    }
}

pub fn reorder(
    id: Option<Value>,
    store: &GroupStore,
    bus: &Arc<EventBus>,
    params: &Value,
) -> Response {
    let Some(obj) = params.as_object() else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "expected object params");
    };
    let ws = obj.get("workspaceID").and_then(|v| v.as_str()).map(str::to_string);
    match store.reorder(obj) {
        Ok(groups) => {
            let _ = bus.publish(
                "group.changed",
                json!({ "workspaceID": ws, "change": "reordered" }),
            );
            Response::ok(id, json!({ "groups": groups }))
        }
        Err(e) => group_err(id, e),
    }
}
