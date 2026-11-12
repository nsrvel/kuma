use kuma_domain::{GroupError, KubeConfigError, ServiceError, WorkspaceError};
use kuma_protocol::jsonrpc::{Response, ERR_KUMA};
use serde_json::json;
use serde_json::Value;

pub fn workspace_err(id: Option<Value>, err: WorkspaceError) -> Response {
    Response {
        jsonrpc: "2.0".into(),
        result: None,
        error: Some(kuma_protocol::jsonrpc::RpcError {
            code: ERR_KUMA,
            message: err.message(),
            data: Some(json!({ "kumaCode": err.code() })),
        }),
        id,
    }
}

pub fn group_err(id: Option<Value>, err: GroupError) -> Response {
    Response {
        jsonrpc: "2.0".into(),
        result: None,
        error: Some(kuma_protocol::jsonrpc::RpcError {
            code: ERR_KUMA,
            message: err.message(),
            data: Some(json!({ "kumaCode": err.code() })),
        }),
        id,
    }
}

pub fn kube_err(id: Option<Value>, err: KubeConfigError) -> Response {
    Response {
        jsonrpc: "2.0".into(),
        result: None,
        error: Some(kuma_protocol::jsonrpc::RpcError {
            code: ERR_KUMA,
            message: err.message(),
            data: Some(json!({ "kumaCode": err.code() })),
        }),
        id,
    }
}

pub fn service_err(id: Option<Value>, err: ServiceError) -> Response {
    Response {
        jsonrpc: "2.0".into(),
        result: None,
        error: Some(kuma_protocol::jsonrpc::RpcError {
            code: ERR_KUMA,
            message: err.message(),
            data: Some(json!({ "kumaCode": err.code() })),
        }),
        id,
    }
}
