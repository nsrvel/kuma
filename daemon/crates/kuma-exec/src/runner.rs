use crate::process::{apply_working_dir, provider_type, spawn_managed, trimmed_cmd};
use crate::runtime::{ExecEngine, ExecError};
use serde_json::Value;
use std::process::Command;
use std::sync::Arc;

pub fn start_service(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
) -> Result<(), ExecError> {
    start_service_inner(engine, service_id, provider, false)
}

pub(crate) fn start_service_reconnect(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
) -> Result<(), ExecError> {
    start_service_inner(engine, service_id, provider, true)
}

fn start_service_inner(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let ptype = provider_type(provider);
    match ptype {
        "shell" => start_shell(engine, service_id, provider, is_reconnect),
        "kubernetes" => start_kubernetes(engine, service_id, provider, is_reconnect),
        "docker" | "podman" => start_container(engine, service_id, provider, ptype, is_reconnect),
        "ssh" => start_ssh(engine, service_id, provider, is_reconnect),
        "tunnel" => start_tunnel(engine, service_id, provider, is_reconnect),
        "httpCheck" => start_health(engine, service_id, provider, is_reconnect),
        "processMonitor" => start_monitor(engine, service_id, provider, is_reconnect),
        other => Err(ExecError::Message(format!("unknown provider type {other}"))),
    }
}

pub fn stop_service(engine: &Arc<ExecEngine>, service_id: &str) -> Result<(), ExecError> {
    if let Some(mut child) = engine.take_child(service_id) {
        let _ = child.kill();
        let _ = child.wait();
    }
    engine.set_stopped(service_id);
    Ok(())
}

pub fn restart_service(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
) -> Result<(), ExecError> {
    let _ = stop_service(engine, service_id);
    start_service(engine, service_id, provider)
}

fn start_shell(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let Some(cmd) = trimmed_cmd(provider, "runCommand") else {
        return Err(ExecError::Message("shell provider missing runCommand".into()));
    };
    let mut command = Command::new("sh");
    command.arg("-lc").arg(cmd);
    apply_working_dir(&mut command, provider);
    spawn_managed(
        engine,
        service_id,
        "shell",
        provider,
        command,
        is_reconnect,
    )
}

fn start_kubernetes(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    if let Some(cmd) = trimmed_cmd(provider, "runCommand") {
        let mut command = Command::new("sh");
        command.arg("-lc").arg(cmd);
        apply_working_dir(&mut command, provider);
        return spawn_managed(
            engine,
            service_id,
            "kubernetes",
            provider,
            command,
            is_reconnect,
        );
    }
    let bin = std::env::var("KUMA_KUBECTL_BIN").unwrap_or_else(|_| "kubectl".into());
    let ns = provider
        .get("kubeNamespace")
        .and_then(|v| v.as_str())
        .unwrap_or("default");
    let target = provider
        .get("targetName")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ExecError::Message("kubernetes provider missing targetName".into()))?;
    let mut command = Command::new(bin);
    command
        .arg("port-forward")
        .arg(target)
        .arg(format!("8080:{ns}"))
        .arg("-n")
        .arg(ns);
    spawn_managed(
        engine,
        service_id,
        "kubernetes",
        provider,
        command,
        is_reconnect,
    )
}

fn start_container(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    ptype: &str,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let bin = if ptype == "podman" {
        std::env::var("KUMA_PODMAN_BIN").unwrap_or_else(|_| "podman".into())
    } else {
        std::env::var("KUMA_DOCKER_BIN").unwrap_or_else(|_| "docker".into())
    };
    if let Some(cmd) = trimmed_cmd(provider, "runCommand") {
        let mut command = Command::new("sh");
        command.arg("-lc").arg(cmd);
        apply_working_dir(&mut command, provider);
        return spawn_managed(engine, service_id, ptype, provider, command, is_reconnect);
    }
    let mut command = Command::new(bin);
    command.args(["compose", "up", "-d"]);
    apply_working_dir(&mut command, provider);
    spawn_managed(engine, service_id, ptype, provider, command, is_reconnect)
}

fn start_ssh(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let host = provider
        .get("sshHost")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ExecError::Message("ssh provider missing sshHost".into()))?;
    let user = provider
        .get("sshUser")
        .and_then(|v| v.as_str())
        .unwrap_or("root");
    let port = provider
        .get("sshPort")
        .and_then(|v| v.as_i64())
        .unwrap_or(22);
    let mut command = Command::new("ssh");
    command
        .arg("-N")
        .arg("-L")
        .arg(format!(
            "{}:127.0.0.1:{}",
            port,
            provider
                .get("portMappings")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|m| m.get("localPort"))
                .and_then(|v| v.as_i64())
                .unwrap_or(8080)
        ))
        .arg("-p")
        .arg(port.to_string())
        .arg(format!("{user}@{host}"));
    spawn_managed(engine, service_id, "ssh", provider, command, is_reconnect)
}

fn start_tunnel(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let tunnel_type = provider
        .get("tunnelType")
        .and_then(|v| v.as_str())
        .unwrap_or("cloudflared");
    let target = provider
        .get("tunnelTargetUrl")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ExecError::Message("tunnel missing tunnelTargetUrl".into()))?;
    let command = if tunnel_type == "ngrok" {
        let mut c = Command::new(
            std::env::var("KUMA_NGROK_BIN").unwrap_or_else(|_| "ngrok".into()),
        );
        c.arg("http").arg(target);
        if let Some(tok) = provider.get("ngrokAuthToken").and_then(|v| v.as_str()) {
            if !tok.is_empty() && !tok.contains("***") {
                c.arg("--authtoken").arg(tok);
            }
        }
        c
    } else {
        let mut c = Command::new(
            std::env::var("KUMA_CLOUDFLARED_BIN").unwrap_or_else(|_| "cloudflared".into()),
        );
        c.arg("tunnel").arg("--url").arg(target);
        c
    };
    spawn_managed(engine, service_id, "tunnel", provider, command, is_reconnect)
}

fn start_health(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let url = provider
        .get("httpCheckUrl")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ExecError::Message("httpCheck missing httpCheckUrl".into()))?;
    let interval = provider
        .get("httpCheckInterval")
        .and_then(|v| v.as_i64())
        .unwrap_or(30)
        .max(1);
    let script = format!(
        "while true; do curl -sf {url:?} >/dev/null || exit 1; sleep {interval}; done"
    );
    let mut command = Command::new("sh");
    command.arg("-lc").arg(script);
    spawn_managed(engine, service_id, "httpCheck", provider, command, is_reconnect)
}

fn start_monitor(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider: &Value,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    let name = provider
        .get("monitorProcessName")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| ExecError::Message("processMonitor missing monitorProcessName".into()))?;
    let interval = provider
        .get("monitorInterval")
        .and_then(|v| v.as_i64())
        .unwrap_or(5)
        .max(1);
    let script = format!("while pgrep -x {name:?} >/dev/null; do sleep {interval}; done");
    let mut command = Command::new("sh");
    command.arg("-lc").arg(script);
    spawn_managed(
        engine,
        service_id,
        "processMonitor",
        provider,
        command,
        is_reconnect,
    )
}
