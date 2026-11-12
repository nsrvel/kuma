use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

/// One JSON object per line (NDJSON) on the Unix socket.
pub const FRAMING: &str = "ndjson";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Request {
    pub jsonrpc: String,
    pub method: String,
    #[serde(default)]
    pub params: Value,
    pub id: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Response {
    pub jsonrpc: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
    pub id: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl Request {
    pub fn parse_line(line: &str) -> Result<Self, ParseError> {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return Err(ParseError::EmptyLine);
        }
        if trimmed.len() > crate::MAX_NDJSON_LINE_BYTES {
            return Err(ParseError::LineTooLarge);
        }
        serde_json::from_str(trimmed).map_err(ParseError::InvalidJson)
    }
}

impl Response {
    pub fn ok(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            result: Some(result),
            error: None,
            id,
        }
    }

    pub fn err(id: Option<Value>, code: i32, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            result: None,
            error: Some(RpcError {
                code,
                message: message.into(),
                data: None,
            }),
            id,
        }
    }

    pub fn to_line(&self) -> Result<String, serde_json::Error> {
        let mut line = serde_json::to_string(self)?;
        line.push('\n');
        Ok(line)
    }
}

#[derive(Debug, Error)]
pub enum ParseError {
    #[error("empty line")]
    EmptyLine,
    #[error("line exceeds maximum size")]
    LineTooLarge,
    #[error("invalid JSON-RPC payload")]
    InvalidJson(#[from] serde_json::Error),
}

pub const ERR_PARSE: i32 = -32700;
pub const ERR_METHOD_NOT_FOUND: i32 = -32601;
pub const ERR_INVALID_REQUEST: i32 = -32600;
pub const ERR_KUMA: i32 = -32001;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::methods;

    #[test]
    fn roundtrip_request() {
        let raw = r#"{"jsonrpc":"2.0","method":"daemon.ping","params":{},"id":1}"#;
        let req = Request::parse_line(raw).unwrap();
        assert_eq!(req.method, methods::DAEMON_PING);
        assert_eq!(req.id, Some(Value::from(1)));
    }

    #[test]
    fn response_line_ends_with_newline() {
        let line = Response::ok(Some(1.into()), serde_json::json!({"pong": true}))
            .to_line()
            .unwrap();
        assert!(line.ends_with('\n'));
    }

    #[test]
    fn rejects_oversized_line() {
        let big = "x".repeat(crate::MAX_NDJSON_LINE_BYTES + 1);
        assert!(matches!(
            Request::parse_line(&big),
            Err(ParseError::LineTooLarge)
        ));
    }
}
