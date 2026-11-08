use crate::runtime::{ExecEngine, ExecError};
use serde_json::Value;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub fn spawn_managed(
    engine: &Arc<ExecEngine>,
    service_id: &str,
    provider_type: &str,
    provider: &Value,
    cmd: Command,
    is_reconnect: bool,
) -> Result<(), ExecError> {
    if matches!(
        engine.snapshot(service_id).status.as_str(),
        "running" | "starting" | "reconnecting"
    ) {
        return Err(ExecError::AlreadyRunning);
    }
    if !is_reconnect {
        engine.reset_reconnect_budget(service_id);
        engine.set_starting(service_id);
    } else {
        engine.set_reconnecting(service_id);
    }
    let mut command = cmd;
    command.stdin(Stdio::null());
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| ExecError::Message(e.to_string()))?;
    let out = child.stdout.take();
    let err = child.stderr.take();
    let sid = service_id.to_string();
    let eng = Arc::clone(engine);
    if let Some(o) = out {
        let s = sid.clone();
        let e = Arc::clone(&eng);
        thread::spawn(move || drain_lines(o, &s, &e));
    }
    if let Some(er) = err {
        let s = sid.clone();
        let e = Arc::clone(&eng);
        thread::spawn(move || drain_lines(er, &s, &e));
    }
    engine.set_running_category(service_id, provider_type);
    engine.register_child(service_id, child);
    spawn_exit_watcher(
        Arc::clone(engine),
        service_id.to_string(),
        provider_type.to_string(),
        provider.clone(),
    );
    Ok(())
}

fn spawn_exit_watcher(
    engine: Arc<ExecEngine>,
    service_id: String,
    provider_type: String,
    provider: Value,
) {
    thread::spawn(move || {
        loop {
            thread::sleep(Duration::from_millis(250));
            let exited = {
                let mut children = engine.children.lock().unwrap();
                let Some(child) = children.get_mut(&service_id) else {
                    return;
                };
                match child.try_wait() {
                    Ok(Some(_)) => {
                        children.remove(&service_id);
                        true
                    }
                    Ok(None) => false,
                    Err(_) => {
                        children.remove(&service_id);
                        true
                    }
                }
            };
            if !exited {
                continue;
            }
            engine.set_stopped(&service_id);
            if !auto_reconnect_enabled(&provider) {
                break;
            }
            if !matches!(
                provider_type.as_str(),
                "shell" | "ssh" | "kubernetes"
            ) {
                break;
            }
            if !engine.consume_reconnect_slot(&service_id) {
                // ponytail: 3 attempts per manual start; spec backoff table is future work
                break;
            }
            thread::sleep(Duration::from_millis(500));
            let _ = crate::runner::start_service_reconnect(&engine, &service_id, &provider);
            break;
        }
    });
}

fn auto_reconnect_enabled(provider: &Value) -> bool {
    provider
        .get("autoReconnect")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

fn drain_lines<R: std::io::Read + Send + 'static>(pipe: R, service_id: &str, engine: &ExecEngine) {
    let reader = BufReader::new(pipe);
    for line in reader.lines().map_while(Result::ok) {
        engine.append_log(service_id, line);
    }
}

pub fn provider_type(provider: &Value) -> &str {
    provider
        .get("type")
        .and_then(|v| v.as_str())
        .unwrap_or("shell")
}

pub fn trimmed_cmd(provider: &Value, key: &str) -> Option<String> {
    provider
        .get(key)
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

pub fn apply_working_dir(cmd: &mut Command, provider: &Value) {
    if let Some(wd) = provider.get("workingDirectory").and_then(|v| v.as_str()) {
        if !wd.trim().is_empty() {
            cmd.current_dir(wd.trim());
        }
    }
}
