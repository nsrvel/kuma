use kuma_protocol::jsonrpc::Response;
use kuma_store::EventBus;
use serde_json::{json, Value};
use std::sync::Arc;

pub fn subscribe(id: Option<Value>, bus: &Arc<EventBus>, params: &Value) -> Response {
    let since = params
        .get("sinceSeq")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let topics: Option<Vec<String>> = params.get("topics").and_then(|v| {
        v.as_array().map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(str::to_string))
                .collect()
        })
    });
    let topic_refs = topics.as_deref();
    let (events, replay_from, truncated) = bus.replay(since, topic_refs);
    let subscription_id = bus.subscribe(topics.unwrap_or_default());
    Response::ok(
        id,
        json!({
            "subscriptionId": subscription_id,
            "events": events,
            "replayFromSeq": replay_from,
            "truncated": truncated,
        }),
    )
}

pub fn unsubscribe(id: Option<Value>, bus: &Arc<EventBus>, params: &Value) -> Response {
    let Some(sub) = params.get("subscriptionId").and_then(|v| v.as_str()) else {
        return Response::err(id, kuma_protocol::jsonrpc::ERR_KUMA, "missing subscriptionId");
    };
    let removed = bus.unsubscribe(sub);
    Response::ok(id, json!({ "removed": removed }))
}
