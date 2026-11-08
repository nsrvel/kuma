use kuma_domain::ServiceError;
use serde_json::{Map, Value};

const SSH_FIELDS: &[&str] = &["sshHost", "sshUser", "sshPort", "sshKeyPath", "sshPassword"];
const KUBE_FIELDS: &[&str] = &[
    "kubeConfigID",
    "kubeContext",
    "kubeNamespace",
    "targetName",
    "kubeTargetType",
    "usePattern",
    "yamlConfig",
];
const SHELL_FIELDS: &[&str] = &["runCommand", "workingDirectory"];

pub fn reject_foreign_fields(ptype: &str, params: &Map<String, Value>) -> Result<(), ServiceError> {
    for (key, _) in params {
        if matches!(key.as_str(), "id" | "type" | "label" | "expectedUpdatedAt") {
            continue;
        }
        if ptype == "shell" && (SSH_FIELDS.contains(&key.as_str()) || KUBE_FIELDS.contains(&key.as_str()))
        {
            return Err(ServiceError::InvalidPort {
                message: format!("KUMA_PRV_FIELD_NOT_APPLICABLE: {key} does not apply to shell"),
            });
        }
        if ptype == "ssh" && (SHELL_FIELDS.contains(&key.as_str()) || KUBE_FIELDS.contains(&key.as_str()))
        {
            return Err(ServiceError::InvalidPort {
                message: format!("KUMA_PRV_FIELD_NOT_APPLICABLE: {key} does not apply to ssh"),
            });
        }
        if ptype == "kubernetes"
            && (SSH_FIELDS.contains(&key.as_str()) || SHELL_FIELDS.contains(&key.as_str()))
        {
            return Err(ServiceError::InvalidPort {
                message: format!("KUMA_PRV_FIELD_NOT_APPLICABLE: {key} does not apply to kubernetes"),
            });
        }
    }
    Ok(())
}
