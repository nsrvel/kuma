use super::url::normalize;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::path::Path;

fn blocking(code: impl Into<String>, message: impl Into<String>) -> Value {
    json!({
        "code": code.into(),
        "message": message.into(),
        "severity": "blocking",
    })
}

pub fn configuration_issues(provider: &Value, ports: &[Value], ssh_auth_key: bool) -> Vec<Value> {
    let ptype = provider.get("type").and_then(|v| v.as_str()).unwrap_or("");
    let mut issues = port_issues(ports, ptype);
    issues.extend(match ptype {
        "kubernetes" => kubernetes_issues(provider),
        "docker" | "podman" => compose_issues(provider),
        "shell" => shell_issues(provider),
        "ssh" => ssh_issues(provider, ssh_auth_key),
        "httpCheck" => health_issues(provider),
        "tunnel" => tunnel_issues(provider),
        "processMonitor" => monitor_issues(provider),
        _ => Vec::new(),
    });
    issues
}

fn port_issues(ports: &[Value], ptype: &str) -> Vec<Value> {
    if ptype != "kubernetes" && ptype != "ssh" {
        return Vec::new();
    }
    let mut issues = Vec::new();
    let mut locals = Vec::new();
    for (i, row) in ports.iter().enumerate() {
        let local = row.get("localPort").and_then(|v| v.as_u64());
        let remote = row.get("remotePort").and_then(|v| v.as_u64());
        let both_missing = local.unwrap_or(0) == 0 && remote.unwrap_or(0) == 0;
        if both_missing {
            continue;
        }
        let ok = |p: Option<u64>| p.map(|n| (1..=65535).contains(&n)).unwrap_or(false);
        if !ok(local) || !ok(remote) {
            issues.push(blocking(
                format!("ports.invalid_row_{i}"),
                format!(
                    "Port row {}: enter local and remote ports (1–65535).",
                    i + 1
                ),
            ));
            continue;
        }
        locals.push(local.unwrap());
    }
    if locals.is_empty() {
        issues.push(blocking(
            "ports.required",
            "Add at least one complete port mapping (local and remote).",
        ));
        return issues;
    }
    let unique: HashSet<_> = locals.iter().copied().collect();
    if unique.len() != locals.len() {
        issues.push(blocking(
            "ports.duplicate_local",
            "Each local port must be unique.",
        ));
    }
    issues
}

fn kubernetes_issues(provider: &Value) -> Vec<Value> {
    let mut issues = Vec::new();
    let kid = provider
        .get("kubeConfigID")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty());
    if kid.is_none() {
        issues.push(blocking("k8s.kubeconfig", "Select a kubeconfig."));
    }
    let ctx = provider
        .get("kubeContext")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if ctx.is_empty() {
        issues.push(blocking("k8s.context", "Select a Kubernetes context."));
    }
    let target = provider
        .get("targetName")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if target.is_empty() {
        issues.push(blocking(
            "k8s.target",
            "Enter a target name (pod, service, or pattern).",
        ));
    }
    issues
}

fn compose_issues(provider: &Value) -> Vec<Value> {
    let mut issues = Vec::new();
    let path = provider
        .get("composeFilePath")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let yaml = provider
        .get("yamlConfig")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if path.is_empty() && yaml.is_empty() {
        issues.push(blocking(
            "compose.missing",
            "Choose a compose file or paste compose YAML.",
        ));
        return issues;
    }
    if !path.is_empty() && !Path::new(path).exists() {
        issues.push(blocking(
            "compose.invalid",
            format!("Compose file not found: {path}"),
        ));
    }
    if let Some(script) = provider
        .get("initialScriptPath")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let expanded = if let Some(rest) = script.strip_prefix("~/") {
            if let Ok(home) = std::env::var("HOME") {
                format!("{home}/{rest}")
            } else {
                script.to_string()
            }
        } else {
            script.to_string()
        };
        if !Path::new(&expanded).is_file() {
            issues.push(blocking(
                "compose.startup_script",
                format!("Startup script file not found: {script}"),
            ));
        }
    }
    issues
}

fn shell_issues(provider: &Value) -> Vec<Value> {
    let cmd = provider
        .get("runCommand")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if cmd.is_empty() {
        return vec![blocking("shell.command", "Enter a shell command to run.")];
    }
    Vec::new()
}

fn ssh_issues(provider: &Value, auth_key: bool) -> Vec<Value> {
    let mut issues = Vec::new();
    let host = provider
        .get("sshHost")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if host.is_empty() {
        issues.push(blocking("ssh.host", "SSH host is required."));
    }
    let user = provider
        .get("sshUser")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if user.is_empty() {
        issues.push(blocking("ssh.user", "SSH user is required."));
    }
    if auth_key {
        let key = provider
            .get("sshKeyPath")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        if key.is_empty() {
            issues.push(blocking("ssh.key", "SSH private key path is required."));
        }
    }
    issues
}

fn health_issues(provider: &Value) -> Vec<Value> {
    let raw = provider
        .get("httpCheckUrl")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if raw.is_empty() {
        return vec![blocking("health.url", "Health check URL is required.")];
    }
    if normalize(raw).is_none() {
        return vec![blocking(
            "health.url_invalid",
            "Health check URL is not valid.",
        )];
    }
    Vec::new()
}

fn tunnel_issues(provider: &Value) -> Vec<Value> {
    let target = provider
        .get("tunnelTargetUrl")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if target.is_empty() {
        vec![blocking("tunnel.target", "Tunnel target URL is required.")]
    } else {
        Vec::new()
    }
}

fn monitor_issues(provider: &Value) -> Vec<Value> {
    let name = provider
        .get("monitorProcessName")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if name.is_empty() {
        vec![blocking(
            "monitor.name",
            "Process name to monitor is required.",
        )]
    } else {
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn dt_validation_port_rows_kubernetes() {
        let issues = configuration_issues(
            &json!({"type": "kubernetes", "kubeConfigID": "k", "kubeContext": "c", "targetName": "p"}),
            &[json!({"localPort": 0, "remotePort": 0})],
            true,
        );
        assert!(issues.iter().any(|i| i["code"] == "ports.required"));
        let issues = configuration_issues(
            &json!({"type": "kubernetes", "kubeConfigID": "k", "kubeContext": "c", "targetName": "p"}),
            &[json!({"localPort": 1, "remotePort": 2})],
            true,
        );
        assert!(issues.is_empty());
    }

    #[test]
    fn dt_validation_provider_types() {
        let k8s = configuration_issues(&json!({"type": "kubernetes"}), &[], true);
        assert!(k8s.iter().any(|i| i["code"] == "k8s.kubeconfig"));
        let shell = configuration_issues(&json!({"type": "shell"}), &[], true);
        assert!(shell.iter().any(|i| i["code"] == "shell.command"));
        let health = configuration_issues(
            &json!({"type": "httpCheck", "httpCheckUrl": "not a url"}),
            &[],
            true,
        );
        assert!(health.iter().any(|i| i["code"] == "health.url_invalid"));
        let ok_health = configuration_issues(
            &json!({"type": "httpCheck", "httpCheckUrl": "http://127.0.0.1"}),
            &[],
            true,
        );
        assert!(ok_health.is_empty());
        assert!(!configuration_issues(&json!({"type": "tunnel"}), &[], true).is_empty());
        assert!(!configuration_issues(&json!({"type": "processMonitor"}), &[], true).is_empty());
        assert!(!configuration_issues(&json!({"type": "ssh"}), &[], true).is_empty());
    }

    #[test]
    fn dt_validation_compose_path_or_yaml() {
        let missing = configuration_issues(&json!({"type": "docker"}), &[], true);
        assert!(missing.iter().any(|i| i["code"] == "compose.missing"));
        let yaml_ok = configuration_issues(
            &json!({"type": "podman", "yamlConfig": "services:\n  x:\n    image: x"}),
            &[],
            true,
        );
        assert!(yaml_ok.is_empty());
    }
}
