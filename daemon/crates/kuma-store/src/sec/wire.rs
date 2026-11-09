use crate::Vault;
use serde_json::{json, Map, Value};

const REDACT: &str = "***";

pub fn redact_provider(mut p: Value) -> Value {
    if let Some(obj) = p.as_object_mut() {
        redact_provider_obj(obj);
    }
    p
}

fn redact_provider_obj(obj: &mut Map<String, Value>) {
    for key in ["sshPassword", "ngrokAuthToken"] {
        if obj
            .get(key)
            .and_then(|v| v.as_str())
            .is_some_and(|s| !s.is_empty())
        {
            obj.insert(key.to_string(), json!(REDACT));
            obj.insert(format!("{key}Set"), json!(true));
        }
    }
}

pub fn is_encrypted_at_rest(stored: &str) -> bool {
    let t = stored.trim();
    t.starts_with("kuma:v1:")
        || (t.matches(':').count() == 2
            && !t
                .lines()
                .next()
                .is_some_and(|l| l.starts_with("apiVersion:")))
}

pub fn decrypt_provider_fields(
    vault: &Vault,
    obj: &mut Map<String, Value>,
) -> Result<(), kuma_domain::StoreError> {
    for key in ["sshPassword", "ngrokAuthToken"] {
        if let Some(v) = obj.get(key).and_then(|x| x.as_str()) {
            if v.is_empty() {
                continue;
            }
            let plain = vault.decrypt_field(v)?;
            obj.insert(key.to_string(), json!(plain));
        }
    }
    Ok(())
}

pub fn encrypt_provider_secret(
    vault: &Vault,
    plain: &str,
) -> Result<String, kuma_domain::StoreError> {
    if plain.is_empty() || plain == REDACT {
        return Ok(String::new());
    }
    vault.encrypt_field(plain)
}

pub fn encrypt_kube_config_content(
    vault: &Vault,
    plain: &str,
) -> Result<String, kuma_domain::StoreError> {
    if plain.is_empty() {
        return Ok(String::new());
    }
    vault.encrypt_field(plain)
}

pub fn decrypt_kube_config_content(
    vault: &Vault,
    stored: &str,
) -> Result<String, kuma_domain::StoreError> {
    if stored.is_empty() {
        return Ok(String::new());
    }
    if is_encrypted_at_rest(stored) {
        return vault.decrypt_field(stored);
    }
    Ok(stored.to_string())
}

pub fn provider_for_runner(
    vault: &Vault,
    mut p: Value,
    reveal: bool,
) -> Result<Value, kuma_domain::StoreError> {
    if let Some(obj) = p.as_object_mut() {
        decrypt_provider_fields(vault, obj)?;
        if !reveal {
            redact_provider_obj(obj);
        }
    }
    Ok(p)
}
