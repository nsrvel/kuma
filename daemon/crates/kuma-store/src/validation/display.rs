use serde_json::Value;

fn trim_opt(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .trim()
        .to_string()
}

pub fn display_name(provider: &Value, service_name: &str) -> String {
    let ptype = provider
        .get("type")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if let Some(label) = provider.get("label").and_then(|v| v.as_str()) {
        if !label.trim().is_empty() {
            return label.to_string();
        }
    }
    let sidebar = service_name.trim();
    match ptype {
        "docker" => compose_display(provider, "Docker"),
        "podman" => compose_display(provider, "Podman"),
        "kubernetes" => {
            let t = trim_opt(provider, "targetName");
            if t.is_empty() {
                "Kubernetes".into()
            } else {
                format!("k8s: {t}")
            }
        }
        "shell" => {
            let c = trim_opt(provider, "runCommand");
            if c.is_empty() {
                sidebar.into()
            } else {
                c
            }
        }
        "ssh" => {
            let host = trim_opt(provider, "sshHost");
            let user = trim_opt(provider, "sshUser");
            let port = provider
                .get("sshPort")
                .and_then(|v| v.as_i64())
                .unwrap_or(22);
            format!("SSH: {user}@{host}:{port}")
        }
        "httpCheck" => {
            let u = trim_opt(provider, "httpCheckUrl");
            if u.is_empty() {
                "HTTP".into()
            } else {
                format!("HTTP: {u}")
            }
        }
        "tunnel" => {
            let engine = trim_opt(provider, "tunnelType");
            let target = trim_opt(provider, "tunnelTargetUrl");
            let name = match engine.as_str() {
                "ngrok" => "Ngrok Tunnel",
                _ => "Cloudflare Tunnel",
            };
            format!("{name} -> {target}")
        }
        "processMonitor" => {
            let n = trim_opt(provider, "monitorProcessName");
            if n.is_empty() {
                format!("Monitor: {sidebar}")
            } else {
                format!("Monitor: {n}")
            }
        }
        _ => sidebar.into(),
    }
}

fn compose_display(provider: &Value, prefix: &str) -> String {
    let path = trim_opt(provider, "composeFilePath");
    if !path.is_empty() {
        let name = std::path::Path::new(&path)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("compose");
        return format!("{prefix}: {name}");
    }
    if let Some(img) = extract_compose_image(provider) {
        return format!("{prefix}: {img}");
    }
    let label = provider
        .get("label")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty());
    if let Some(l) = label {
        return format!("{prefix}: {l}");
    }
    prefix.into()
}

pub fn extract_compose_image(provider: &Value) -> Option<String> {
    let yaml = provider.get("yamlConfig").and_then(|v| v.as_str())?;
    for line in yaml.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("image:") {
            let img = rest.trim().trim_matches('"').trim();
            if !img.is_empty() {
                let short = img
                    .trim_start_matches("docker.io/library/")
                    .trim_start_matches("docker.io/")
                    .trim_start_matches("library/");
                return Some(short.to_string());
            }
        }
    }
    None
}
