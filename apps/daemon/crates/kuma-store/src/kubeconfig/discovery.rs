//! Live `k8s.namespaces` / `k8s.resources` discovery against the in-use cluster.
//!
//! Results are cached for the same window as the connection probe. The key includes
//! the kubeconfig snapshot, so an edited file misses immediately. `refresh=true`
//! bypasses the cache, and kubeconfig update/delete clears it.

use super::{io_err, normalize_id, set_path_mode, ProbeCacheEntry, DEFAULT_ID};
use kuma_domain::KubeConfigError;
use serde_json::{json, Value};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const DISCOVERY_TTL_SECS: u64 = 300;
const KUBECTL_TIMEOUT: Duration = Duration::from_secs(30);

enum KubectlRunError {
    NotFound,
    TimedOut,
    Io(String),
}

struct TempKubeconfig(PathBuf);

impl Drop for TempKubeconfig {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

impl super::KubeConfigStore {
    pub fn list_namespaces(
        &self,
        params: &Value,
        kubectl: Option<&str>,
    ) -> Result<Value, KubeConfigError> {
        let kubectl = require_kubectl(kubectl)?;
        let id = kube_id(params)?;
        let refresh = flag_true(params.get("refresh"));
        let yaml = self.resolved_plain_yaml(&id)?;
        let ctx = resolve_context_name(param_str(params, &["context", "kubeContext"]), &yaml);
        let key = cache_key(
            "namespaces",
            &id,
            ctx.as_deref().unwrap_or(""),
            "",
            "",
            &yaml,
        );
        if !refresh {
            if let Some(hit) = self.discovery_get(&key) {
                return Ok(hit);
            }
        }
        let names = self.kubectl_names(
            kubectl,
            &yaml,
            &["get".into(), "namespaces".into()],
            None,
            ctx.as_deref(),
            "namespaces",
        )?;
        let body = json!({ "namespaces": names });
        self.discovery_put(key, body.clone());
        Ok(body)
    }

    pub fn list_resources(
        &self,
        params: &Value,
        kubectl: Option<&str>,
    ) -> Result<Value, KubeConfigError> {
        let (list_resource, running_only) = map_resource_type(params)?;
        let kubectl = require_kubectl(kubectl)?;
        let id = kube_id(params)?;
        let refresh = flag_true(params.get("refresh"));
        let namespace = param_str(params, &["namespace"]);
        let yaml = self.resolved_plain_yaml(&id)?;
        let ctx = resolve_context_name(param_str(params, &["context", "kubeContext"]), &yaml);
        let key = cache_key(
            "resources",
            &id,
            ctx.as_deref().unwrap_or(""),
            namespace.unwrap_or(""),
            list_resource,
            &yaml,
        );
        if !refresh {
            if let Some(hit) = self.discovery_get(&key) {
                return Ok(hit);
            }
        }
        let mut head = vec!["get".to_string(), list_resource.to_string()];
        if running_only {
            head.push("--field-selector=status.phase=Running".into());
        }
        let names = self.kubectl_names(
            kubectl,
            &yaml,
            &head,
            namespace,
            ctx.as_deref(),
            list_resource,
        )?;
        let body = json!({ "names": &names, "resources": &names });
        self.discovery_put(key, body.clone());
        Ok(body)
    }

    pub(super) fn clear_discovery_cache(&self) {
        if let Ok(mut cache) = self.discovery_cache.lock() {
            cache.clear();
        }
    }

    fn discovery_get(&self, key: &str) -> Option<Value> {
        let now = unix_secs();
        let cache = self.discovery_cache.lock().ok()?;
        let entry = cache.get(key)?;
        if entry.expires_at > now {
            Some(entry.body.clone())
        } else {
            None
        }
    }

    fn discovery_put(&self, key: String, body: Value) {
        let now = unix_secs();
        if let Ok(mut cache) = self.discovery_cache.lock() {
            cache.retain(|_, entry| entry.expires_at > now);
            cache.insert(
                key,
                ProbeCacheEntry {
                    body,
                    expires_at: now + DISCOVERY_TTL_SECS,
                },
            );
        }
    }

    fn kubectl_names(
        &self,
        kubectl: &str,
        yaml: &str,
        head: &[String],
        namespace: Option<&str>,
        ctx: Option<&str>,
        operation: &str,
    ) -> Result<Vec<String>, KubeConfigError> {
        let tmp = write_temp_kubeconfig(yaml)?;
        let mut args = head.to_vec();
        args.push("-o".into());
        args.push("name".into());
        args.push("--kubeconfig".into());
        args.push(tmp.0.display().to_string());
        if let Some(ns) = namespace {
            args.push("-n".into());
            args.push(ns.to_string());
        }
        if let Some(ctx) = ctx {
            args.push("--context".into());
            args.push(ctx.to_string());
        }
        let output = match run_kubectl(kubectl, &args) {
            Ok(output) => output,
            Err(KubectlRunError::NotFound) => return Err(KubeConfigError::KubectlNotFound),
            Err(KubectlRunError::TimedOut) => {
                return Err(KubeConfigError::KubectlFailed {
                    detail: failure_message(operation, "timed out after 30s"),
                });
            }
            Err(KubectlRunError::Io(detail)) => return Err(io_err(&detail)),
        };
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(KubeConfigError::KubectlFailed {
                detail: failure_message(operation, stderr.trim()),
            });
        }
        Ok(parse_names(&output.stdout))
    }
}

fn failure_message(operation: &str, detail: &str) -> String {
    if operation == "namespaces" {
        format!("Kubectl namespaces list error: {detail}")
    } else {
        format!("Kubectl {operation} discovery error: {detail}")
    }
}

fn map_resource_type(params: &Value) -> Result<(&'static str, bool), KubeConfigError> {
    let raw = param_str(params, &["resourceType", "kind"]).unwrap_or("");
    match raw {
        "pod" => Ok(("pods", true)),
        "service" => Ok(("services", false)),
        "deployment" => Ok(("deployments", false)),
        other => Err(KubeConfigError::InvalidEnum {
            field: "resourceType".into(),
            value: other.to_string(),
        }),
    }
}

fn require_kubectl(kubectl: Option<&str>) -> Result<&str, KubeConfigError> {
    let path = kubectl.unwrap_or("").trim();
    if path.is_empty() || !is_executable_file(Path::new(path)) {
        return Err(KubeConfigError::KubectlNotFound);
    }
    Ok(path)
}

fn kube_id(params: &Value) -> Result<String, KubeConfigError> {
    let raw = param_str(params, &["kubeConfigID", "kubeconfigId", "id"]).unwrap_or(DEFAULT_ID);
    normalize_id(raw)
}

fn param_str<'a>(params: &'a Value, keys: &[&str]) -> Option<&'a str> {
    for key in keys {
        if let Some(value) = params.get(*key).and_then(|v| v.as_str()) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return Some(trimmed);
            }
        }
    }
    None
}

fn flag_true(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(flag)) => *flag,
        Some(Value::String(text)) => matches!(text.trim(), "true" | "1" | "yes"),
        _ => false,
    }
}

fn cache_key(op: &str, id: &str, ctx: &str, namespace: &str, kind: &str, yaml: &str) -> String {
    format!(
        "{op}\u{1f}{id}\u{1f}{ctx}\u{1f}{namespace}\u{1f}{kind}\u{1f}{:016x}",
        fingerprint(yaml)
    )
}

fn fingerprint(text: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in text.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn resolve_context_name(stored: Option<&str>, yaml: &str) -> Option<String> {
    let contexts = parse_context_names(yaml);
    let stored_trimmed = stored.unwrap_or("").trim();
    if !stored_trimmed.is_empty() && contexts.iter().any(|name| name == stored_trimmed) {
        return Some(stored_trimmed.to_string());
    }
    if let Some(current) = parse_current_context(yaml) {
        if contexts.iter().any(|name| name == &current) {
            return Some(current);
        }
    }
    contexts.into_iter().next()
}

fn parse_current_context(yaml: &str) -> Option<String> {
    for line in yaml_lines(yaml) {
        let trimmed = line.trim();
        if !trimmed.starts_with("current-context:") {
            continue;
        }
        let mut parts = trimmed.split(':');
        let _ = parts.next();
        let rest = parts.next()?;
        let value = strip_quotes(rest.trim());
        if value.is_empty() {
            return None;
        }
        return Some(value);
    }
    None
}

fn parse_context_names(yaml: &str) -> Vec<String> {
    let mut in_block = false;
    let mut contexts = Vec::new();
    for line in yaml_lines(yaml) {
        let trimmed = line.trim();
        if trimmed.starts_with("contexts:") {
            in_block = true;
            continue;
        }
        if !in_block {
            continue;
        }
        let starts_ws = line.starts_with(' ') || line.starts_with('\t');
        if !starts_ws && trimmed.contains(':') && !trimmed.starts_with('-') {
            break;
        }
        let name_line =
            trimmed.starts_with("- name:") || (trimmed.starts_with("name:") && starts_ws);
        if !name_line {
            continue;
        }
        let Some((_, rest)) = trimmed.split_once("name:") else {
            continue;
        };
        let name = strip_quotes(rest.trim());
        if !name.is_empty() && !contexts.contains(&name) {
            contexts.push(name);
        }
    }
    contexts
}

fn yaml_lines(yaml: &str) -> impl Iterator<Item = &str> {
    yaml.split('\n').map(|line| line.trim_end_matches('\r'))
}

fn strip_quotes(value: &str) -> String {
    value.replace(['"', '\''], "")
}

fn write_temp_kubeconfig(yaml: &str) -> Result<TempKubeconfig, KubeConfigError> {
    let path = std::env::temp_dir().join(format!("kuma-chk-{}.yaml", uuid::Uuid::new_v4()));
    std::fs::write(&path, yaml.trim()).map_err(|e| io_err(&e.to_string()))?;
    set_path_mode(&path, 0o600).ok();
    Ok(TempKubeconfig(path))
}

fn is_executable_file(path: &Path) -> bool {
    std::fs::metadata(path)
        .map(|meta| {
            if meta.is_dir() {
                return false;
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                meta.permissions().mode() & 0o111 != 0
            }
            #[cfg(not(unix))]
            {
                true
            }
        })
        .unwrap_or(false)
}

fn kubectl_timeout() -> Duration {
    #[cfg(test)]
    if let Ok(ms) = std::env::var("KUMA_KUBECTL_TIMEOUT_MS") {
        if let Ok(n) = ms.parse::<u64>() {
            if n > 0 {
                return Duration::from_millis(n);
            }
        }
    }
    KUBECTL_TIMEOUT
}

fn run_kubectl(bin: &str, args: &[String]) -> Result<std::process::Output, KubectlRunError> {
    let mut cmd = Command::new(bin);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // Own process group so a timeout can kill kubectl and anything it spawned.
    #[cfg(unix)]
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(|| {
            libc::setpgid(0, 0);
            Ok(())
        });
    }
    let mut child = cmd.spawn().map_err(|err| {
        if err.kind() == std::io::ErrorKind::NotFound {
            KubectlRunError::NotFound
        } else {
            KubectlRunError::Io(err.to_string())
        }
    })?;
    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();
    let stdout_thread = std::thread::spawn(move || read_pipe(stdout_pipe));
    let stderr_thread = std::thread::spawn(move || read_pipe(stderr_pipe));
    let timeout = kubectl_timeout();
    let started = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() >= timeout => {
                kill_child_group(&mut child);
                let _ = stdout_thread.join();
                let _ = stderr_thread.join();
                return Err(KubectlRunError::TimedOut);
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(15)),
            Err(err) => {
                kill_child_group(&mut child);
                let _ = stdout_thread.join();
                let _ = stderr_thread.join();
                return Err(KubectlRunError::Io(err.to_string()));
            }
        }
    };
    let stdout = stdout_thread.join().unwrap_or_default();
    let stderr = stderr_thread.join().unwrap_or_default();
    Ok(std::process::Output {
        status,
        stdout,
        stderr,
    })
}

fn kill_child_group(child: &mut std::process::Child) {
    #[cfg(unix)]
    unsafe {
        libc::kill(-(child.id() as i32), libc::SIGKILL);
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn read_pipe(pipe: Option<impl Read>) -> Vec<u8> {
    let mut buf = Vec::new();
    if let Some(mut pipe) = pipe {
        let _ = pipe.read_to_end(&mut buf);
    }
    buf
}

fn parse_names(stdout: &[u8]) -> Vec<String> {
    let text = String::from_utf8_lossy(stdout);
    let mut names = Vec::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let name = trimmed
            .rsplit_once('/')
            .map(|(_, rest)| rest)
            .unwrap_or(trimmed);
        if !name.is_empty() {
            names.push(name.to_string());
        }
    }
    names.sort();
    names
}

fn unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn resolve_context_prefers_stored_then_current_then_first() {
        let yaml = "current-context: \"dev\"\ncontexts:\n- name: prod\n  name: dev\nclusters:\n";
        assert_eq!(
            resolve_context_name(Some("prod"), yaml).as_deref(),
            Some("prod")
        );
        assert_eq!(
            resolve_context_name(Some("nope"), yaml).as_deref(),
            Some("dev")
        );
        assert_eq!(resolve_context_name(None, yaml).as_deref(), Some("dev"));
        let bare = "contexts:\n- name: only\n";
        assert_eq!(resolve_context_name(None, bare).as_deref(), Some("only"));
    }

    #[test]
    fn parse_names_strips_kind_and_sorts() {
        let names = parse_names(b"namespace/zeta\nnamespace/alpha\n\npod/web\n");
        assert_eq!(names, vec!["alpha", "web", "zeta"]);
    }

    #[test]
    fn kubectl_list_times_out() {
        let path = std::env::temp_dir().join(format!("kuma-sleep-{}.sh", uuid::Uuid::new_v4()));
        {
            let mut file = std::fs::File::create(&path).unwrap();
            writeln!(file, "#!/bin/sh\nsleep 5\n").unwrap();
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        std::env::set_var("KUMA_KUBECTL_TIMEOUT_MS", "200");
        let started = Instant::now();
        let err = run_kubectl(&path.display().to_string(), &[]).unwrap_err();
        assert!(matches!(err, KubectlRunError::TimedOut));
        assert!(started.elapsed() < Duration::from_secs(2));
        std::env::remove_var("KUMA_KUBECTL_TIMEOUT_MS");
        let _ = std::fs::remove_file(path);
    }
}
