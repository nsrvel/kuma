use anyhow::Result;
use kuma_client::DaemonClient;
use kuma_protocol::methods;
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

/// MCP stdio server: `initialize`, `tools/list`, `tools/call` → daemon JSON-RPC.
pub async fn run_stdio_mcp() -> Result<()> {
    let mut client = DaemonClient::connect_mcp(kuma_protocol::paths::socket_path()).await?;
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let msg: Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(e) => {
                write_mcp_error(None, -32700, &format!("parse error: {e}"))?;
                continue;
            }
        };
        let id = msg.get("id").cloned();
        let method = msg.get("method").and_then(|v| v.as_str()).unwrap_or("");
        let resp = match method {
            "initialize" => json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": { "tools": {} },
                    "serverInfo": { "name": "kuma", "version": "0.1.0" },
                }
            }),
            "tools/list" => json!({
                "jsonrpc": "2.0",
                "id": id,
                "result": { "tools": mcp_tools() },
            }),
            "tools/call" => {
                let params = msg.get("params").and_then(|v| v.as_object());
                let tool = params
                    .and_then(|p| p.get("name"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let args = params
                    .and_then(|p| p.get("arguments"))
                    .cloned()
                    .unwrap_or(json!({}));
                match call_tool(&mut client, tool, args).await {
                    Ok(content) => json!({
                        "jsonrpc": "2.0",
                        "id": id,
                        "result": {
                            "content": [{ "type": "text", "text": content }],
                            "isError": false,
                        }
                    }),
                    Err(e) => json!({
                        "jsonrpc": "2.0",
                        "id": id,
                        "result": {
                            "content": [{ "type": "text", "text": e.to_string() }],
                            "isError": true,
                        }
                    }),
                }
            }
            _ => {
                write_mcp_error(id, -32601, &format!("method not found: {method}"))?;
                continue;
            }
        };
        writeln!(io::stdout(), "{}", serde_json::to_string(&resp)?)?;
        io::stdout().flush()?;
    }
    Ok(())
}

async fn call_tool(client: &mut DaemonClient, tool: &str, args: Value) -> Result<String> {
    let rpc = methods::mcp_tool_to_rpc(tool).unwrap_or(tool);
    let params = if args.as_object().map(|o| o.is_empty()).unwrap_or(true) {
        json!({})
    } else {
        args
    };
    let v = client.call(rpc, params).await?;
    let text = serde_json::to_string_pretty(&v)?;
    Ok(strip_secret_fields(&text))
}

fn strip_secret_fields(text: &str) -> String {
    text.replace("\"sshPassword\"", "\"sshPasswordRedacted\"")
}

fn mcp_tools() -> Vec<Value> {
    methods::all_method_names()
        .into_iter()
        .filter(|m| *m != methods::DAEMON_ROTATE_API_TOKEN)
        .map(|m| {
            let tool_name = methods::rpc_to_mcp_tool(m);
            json!({
                "name": tool_name,
                "description": m,
                "inputSchema": { "type": "object" },
            })
        })
        .collect()
}

fn write_mcp_error(id: Option<Value>, code: i64, message: &str) -> Result<()> {
    let resp = json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": { "code": code, "message": message },
    });
    writeln!(io::stdout(), "{}", serde_json::to_string(&resp)?)?;
    Ok(())
}
