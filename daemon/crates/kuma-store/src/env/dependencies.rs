use crate::env::path::PathResolver;
use crate::env::resolve::{read_settings_path, resolve_executable};
use crate::settings::{expand_tilde, validate_custom_binary};
use crate::SettingsStore;
use serde_json::{json, Value};

pub fn dependencies(settings: &SettingsStore, path_resolver: &PathResolver) -> Value {
    let (kubectl, kube_custom, docker, podman, cloudflared, ngrok) = {
        let conn_arc = settings.connection();
        let conn = conn_arc.lock().unwrap();
        (
            read_settings_path(
                &conn,
                "kuma.settings.customKubectlPath",
                Some("kuma.custom_kubectl_path"),
            ),
            read_settings_path(
                &conn,
                "kuma.settings.customKubeconfigPath",
                Some("kuma.custom_kubeconfig_path"),
            ),
            read_settings_path(
                &conn,
                "kuma.settings.customDockerPath",
                Some("kuma.custom_docker_path"),
            ),
            read_settings_path(
                &conn,
                "kuma.settings.customPodmanPath",
                Some("kuma.custom_podman_path"),
            ),
            read_settings_path(
                &conn,
                "kuma.settings.cloudflaredPath",
                Some("kuma.custom_cloudflared_path"),
            ),
            read_settings_path(
                &conn,
                "kuma.settings.customNgrokPath",
                Some("kuma.custom_ngrok_path"),
            ),
        )
    };
    let engines = [
        engine(
            "kubectl",
            "kubectl",
            "Terminal",
            "Run kubectl commands",
            "kuma.settings.customKubectlPath",
            kubectl,
            "kubectl",
            settings,
            path_resolver,
        ),
        kubeconfig_engine_from_custom(kube_custom),
        engine(
            "docker",
            "docker",
            "ShippingBox",
            "Run Docker containers",
            "kuma.settings.customDockerPath",
            docker,
            "docker",
            settings,
            path_resolver,
        ),
        engine(
            "podman",
            "podman",
            "ShippingBox",
            "Run Podman containers",
            "kuma.settings.customPodmanPath",
            podman,
            "podman",
            settings,
            path_resolver,
        ),
    ];
    let tunneling = [
        engine(
            "cloudflared",
            "cloudflared",
            "Cloud",
            "Cloudflare Tunnel",
            "kuma.settings.cloudflaredPath",
            cloudflared,
            "cloudflared",
            settings,
            path_resolver,
        ),
        engine(
            "ngrok",
            "ngrok",
            "Network",
            "ngrok tunnel",
            "kuma.settings.customNgrokPath",
            ngrok,
            "ngrok",
            settings,
            path_resolver,
        ),
    ];
    json!({ "engines": engines, "tunneling": tunneling })
}

#[allow(clippy::too_many_arguments)]
fn engine(
    name: &str,
    _icon: &str,
    icon_name: &str,
    description: &str,
    settings_key: &str,
    custom: String,
    command: &str,
    settings: &SettingsStore,
    path_resolver: &PathResolver,
) -> Value {
    let resolved = resolve_executable(
        command,
        if custom.is_empty() {
            None
        } else {
            Some(&custom)
        },
        true,
        settings,
        path_resolver,
    );
    let path = resolved["path"].as_str();
    let is_installed = path.is_some();
    json!({
        "name": name,
        "iconName": icon_name,
        "description": description,
        "settingsKey": settings_key,
        "category": if name == "kubectl" || name == "docker" || name == "podman" { "engines" } else { "tunneling" },
        "path": if custom.is_empty() { path.map(|s| s.to_string()).unwrap_or_default() } else { custom.clone() },
        "resolvedPath": path,
        "isInstalled": is_installed,
        "status": if is_installed { "available" } else { "missing" },
        "version": Value::Null,
    })
}

fn kubeconfig_engine_from_custom(custom: String) -> Value {
    let resolved = resolved_kubeconfig_path(custom.as_str());
    let is_installed = resolved.is_some();
    json!({
        "name": "kubeconfig",
        "iconName": "doc",
        "description": "Default kubeconfig",
        "settingsKey": "kuma.settings.customKubeconfigPath",
        "category": "engines",
        "path": if custom.is_empty() { resolved.clone().unwrap_or_else(|| "~/.kube/config".into()) } else { custom },
        "resolvedPath": resolved,
        "isInstalled": is_installed,
        "status": if is_installed { "available" } else { "missing" },
        "version": Value::Null,
    })
}

fn resolved_kubeconfig_path(custom: &str) -> Option<String> {
    if !custom.trim().is_empty() {
        let p = expand_tilde(custom.trim());
        if p.exists() {
            return Some(p.to_string_lossy().into_owned());
        }
    }
    if let Ok(kc) = std::env::var("KUBECONFIG") {
        for part in kc.split(':').filter(|p| !p.is_empty()) {
            let p = expand_tilde(part);
            if p.exists() {
                return Some(p.to_string_lossy().into_owned());
            }
        }
    }
    let home = std::env::var("HOME").ok()?;
    let default = format!("{home}/.kube/config");
    if std::path::Path::new(&default).exists() {
        Some(default)
    } else {
        None
    }
}

pub fn validate_binary(path: &str, expected_command: &str) -> Value {
    validate_custom_binary(path, expected_command).to_json(Some(path.to_string()))
}
