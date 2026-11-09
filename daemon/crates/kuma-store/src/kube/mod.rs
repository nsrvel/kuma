//! §07 target name parsing (pattern + kind/name).

use serde_json::{json, Value};

/// Resolve `targetName` to kubectl reference shape for API consumers.
pub fn resolve_target(target: &str, use_pattern: bool) -> Value {
    let t = target.trim();
    if t.is_empty() {
        return json!({
            "kind": Value::Null,
            "name": Value::Null,
            "kubectlReference": Value::Null,
            "resolvedTarget": Value::Null,
            "usePattern": use_pattern,
            "matched": false,
            "liveTarget": Value::Null,
        });
    }
    let (kind, name) = if let Some((k, n)) = t.split_once('/') {
        (k.to_string(), n.to_string())
    } else if use_pattern || t.contains('*') || t.contains('?') {
        ("pattern".into(), t.to_string())
    } else {
        ("pod".into(), t.to_string())
    };
    let kubectl_reference = format!("{kind}/{name}");
    json!({
        "kind": kind,
        "name": name,
        "kubectlReference": kubectl_reference,
        "resolvedTarget": t,
        "usePattern": use_pattern,
        "matched": true,
        "liveTarget": Value::Null,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dt_k8s_resolve_target_kind_name() {
        let v = resolve_target("deploy/nginx", true);
        assert_eq!(v["kind"], "deploy");
        assert_eq!(v["name"], "nginx");
        assert_eq!(v["kubectlReference"], "deploy/nginx");
    }

    #[test]
    fn dt_k8s_resolve_target_pattern() {
        let v = resolve_target("redis-*", true);
        assert_eq!(v["kind"], "pattern");
        assert_eq!(v["matched"], true);
    }
}
