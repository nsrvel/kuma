//! Client for the daemon Unix socket (NDJSON JSON-RPC 2.0).

use kuma_protocol::jsonrpc::{Request, Response, ERR_PARSE};
use kuma_protocol::methods;
use kuma_protocol::paths;
use serde_json::Value;
use std::path::Path;
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use tokio::net::unix::{OwnedReadHalf, OwnedWriteHalf};

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("rpc error {code}: {message}")]
    Rpc { code: i32, message: String },
    #[error("unexpected response")]
    UnexpectedResponse,
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, ClientError>;

/// Connected daemon client (one in-flight request at a time).
pub struct DaemonClient {
    reader: BufReader<OwnedReadHalf>,
    writer: OwnedWriteHalf,
    next_id: u64,
}

impl DaemonClient {
    pub async fn connect_socket(path: impl AsRef<Path>) -> Result<Self> {
        Self::connect_with_kind(path, "cli").await
    }

    pub async fn connect_mcp(path: impl AsRef<Path>) -> Result<Self> {
        Self::connect_with_kind(path, "mcp").await
    }

    async fn connect_with_kind(path: impl AsRef<Path>, client_kind: &str) -> Result<Self> {
        let stream = UnixStream::connect(path.as_ref()).await?;
        let (reader, writer) = stream.into_split();
        let mut client = Self {
            reader: BufReader::new(reader),
            writer,
            next_id: 1,
        };
        let _ = client
            .call(
                methods::DAEMON_PING,
                serde_json::json!({ "clientKind": client_kind }),
            )
            .await;
        Ok(client)
    }

    pub async fn connect_default() -> Result<Self> {
        Self::connect_socket(paths::socket_path()).await
    }

    pub async fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        let id = self.next_id;
        self.next_id += 1;
        let req = Request {
            jsonrpc: "2.0".into(),
            method: method.into(),
            params,
            id: Some(id.into()),
        };
        let mut line = serde_json::to_string(&req)?;
        line.push('\n');
        self.writer.write_all(line.as_bytes()).await?;

        let mut response_line = String::new();
        self.reader.read_line(&mut response_line).await?;
        if response_line.trim().is_empty() {
            return Err(ClientError::UnexpectedResponse);
        }
        let resp: Response = serde_json::from_str(response_line.trim())?;
        if let Some(err) = resp.error {
            return Err(ClientError::Rpc {
                code: err.code,
                message: err.message,
            });
        }
        resp.result.ok_or(ClientError::UnexpectedResponse)
    }

    pub async fn ping(&mut self) -> Result<Value> {
        self.call(methods::DAEMON_PING, serde_json::json!({})).await
    }

    pub async fn status(&mut self) -> Result<Value> {
        self.call(methods::DAEMON_STATUS, serde_json::json!({})).await
    }
}

impl DaemonClient {
    /// Parse a single response line (used in tests).
    pub fn parse_response_line(line: &str) -> std::result::Result<Response, ClientError> {
        if line.trim().is_empty() {
            return Err(ClientError::Rpc {
                code: ERR_PARSE,
                message: "empty line".into(),
            });
        }
        Ok(serde_json::from_str(line.trim())?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_ok_response() {
        let line = r#"{"jsonrpc":"2.0","result":{"pong":true},"id":1}"#;
        let resp = DaemonClient::parse_response_line(line).unwrap();
        assert!(resp.result.unwrap()["pong"].as_bool().unwrap());
    }
}
