//! REST routes from docs/specs/daemon/mcp-tools.csv (`rest_endpoint` column).

use axum::http::Method;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct RestRoute {
    pub method: Method,
    /// Axum path under `/v1` (e.g. `/services/:serviceId`).
    pub path: String,
    pub rpc_method: String,
}

const CSV: &str = include_str!("../../../../docs/specs/daemon/mcp-tools.csv");

pub fn load_routes() -> Vec<RestRoute> {
    let mut out = Vec::new();
    for line in CSV.lines().skip(1) {
        let Some((endpoint, rpc)) = parse_csv_line(line) else {
            continue;
        };
        if endpoint.is_empty() || rpc == "daemon.rotate_api_token" {
            continue;
        }
        let Some((http, path)) = split_endpoint(&endpoint) else {
            continue;
        };
        let axum_path = csv_path_to_axum(&path);
        let method = match http.as_str() {
            "GET" => Method::GET,
            "POST" => Method::POST,
            "PUT" => Method::PUT,
            "PATCH" => Method::PATCH,
            "DELETE" => Method::DELETE,
            _ => continue,
        };
        out.push(RestRoute {
            method,
            path: axum_path,
            rpc_method: rpc,
        });
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out.dedup_by(|a, b| a.method == b.method && a.path == b.path);
    out
}

pub fn route_keys() -> Vec<String> {
    load_routes()
        .into_iter()
        .map(|r| format!("{} {}", r.method.as_str(), r.path))
        .collect()
}

pub fn find_route(method: &Method, path: &str) -> Option<RestRoute> {
    load_routes()
        .into_iter()
        .find(|r| r.method == *method && r.path == path)
}

/// Match `path` against registered patterns; returns route + captured params.
pub fn match_route(method: &Method, path: &str) -> Option<(RestRoute, HashMap<String, String>)> {
    for route in load_routes() {
        if route.method != *method {
            continue;
        }
        if let Some(caps) = match_pattern(&route.path, path) {
            return Some((route, caps));
        }
    }
    None
}

pub fn path_params_to_rpc(caps: &HashMap<String, String>) -> serde_json::Map<String, serde_json::Value> {
    let mut m = serde_json::Map::new();
    if let (Some(sid), Some(gid)) = (caps.get("serviceId"), caps.get("groupId")) {
        m.insert("id".into(), serde_json::Value::String(sid.clone()));
        m.insert("groupID".into(), serde_json::Value::String(gid.clone()));
        return m;
    }
    if let Some(sid) = caps.get("serviceId") {
        m.insert("id".into(), serde_json::Value::String(sid.clone()));
        m.insert("serviceID".into(), serde_json::Value::String(sid.clone()));
    }
    if let Some(wid) = caps.get("workspaceId") {
        m.insert("workspaceID".into(), serde_json::Value::String(wid.clone()));
    }
    if let Some(gid) = caps.get("groupId") {
        m.insert("id".into(), serde_json::Value::String(gid.clone()));
        m.insert("groupID".into(), serde_json::Value::String(gid.clone()));
    }
    if let Some(pid) = caps.get("providerId") {
        m.insert("id".into(), serde_json::Value::String(pid.clone()));
    }
    if let Some(kid) = caps.get("kubeconfigId") {
        m.insert("id".into(), serde_json::Value::String(kid.clone()));
    }
    if let Some(key) = caps.get("key") {
        m.insert("key".into(), serde_json::Value::String(key.clone()));
    }
    if let Some(sub) = caps.get("subscriptionId") {
        m.insert("subscriptionID".into(), serde_json::Value::String(sub.clone()));
    }
    m
}

fn parse_csv_line(line: &str) -> Option<(String, String)> {
    let mut fields = Vec::new();
    let mut cur = String::new();
    let mut in_quotes = false;
    for c in line.chars() {
        match c {
            '"' => in_quotes = !in_quotes,
            ',' if !in_quotes => {
                fields.push(std::mem::take(&mut cur));
            }
            _ => cur.push(c),
        }
    }
    fields.push(cur);
    if fields.len() < 6 {
        return None;
    }
    let endpoint = fields[4].trim().to_string();
    let rpc = fields[5].trim().to_string();
    Some((endpoint, rpc))
}

fn split_endpoint(raw: &str) -> Option<(String, String)> {
    let first = raw.split(';').next()?.trim();
    let mut parts = first.split_whitespace();
    let http = parts.next()?.to_string();
    let path = parts.next()?.to_string();
    Some((http, path))
}

fn csv_path_to_axum(path: &str) -> String {
    let without = path.strip_prefix("/v1").unwrap_or(path);
    without
        .replace("{workspaceId}", ":workspaceId")
        .replace("{serviceId}", ":serviceId")
        .replace("{groupId}", ":groupId")
        .replace("{providerId}", ":providerId")
        .replace("{kubeconfigId}", ":kubeconfigId")
        .replace("{subscriptionId}", ":subscriptionId")
        .replace("{key}", ":key")
}

fn match_pattern(pattern: &str, path: &str) -> Option<HashMap<String, String>> {
    let pat: Vec<&str> = pattern.trim_start_matches('/').split('/').collect();
    let actual: Vec<&str> = path.trim_start_matches('/').split('/').collect();
    if pat.len() != actual.len() {
        return None;
    }
    let mut caps = HashMap::new();
    for (p, a) in pat.iter().zip(actual.iter()) {
        if let Some(name) = p.strip_prefix(':') {
            caps.insert(name.to_string(), (*a).to_string());
        } else if p != a {
            return None;
        }
    }
    Some(caps)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_has_daemon_ping() {
        let routes = load_routes();
        assert!(routes.iter().any(|r| {
            r.rpc_method == "daemon.ping" && r.path == "/daemon/ping"
        }));
    }

    #[test]
    fn match_service_get() {
        let caps = match_pattern(
            "/services/:serviceId",
            "/services/AAA-BBB",
        )
        .unwrap();
        assert_eq!(caps.get("serviceId").unwrap(), "AAA-BBB");
    }
}
