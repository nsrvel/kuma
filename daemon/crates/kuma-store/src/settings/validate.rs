use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Validation {
    pub status: &'static str,
    pub is_valid: bool,
    pub error_message: Option<String>,
    pub code: Option<&'static str>,
}

impl Validation {
    pub fn empty() -> Self {
        Self {
            status: "empty",
            is_valid: false,
            error_message: None,
            code: None,
        }
    }

    pub fn valid(_path: String) -> Self {
        Self {
            status: "valid",
            is_valid: true,
            error_message: None,
            code: None,
        }
    }

    pub fn to_json(&self, path: Option<String>) -> serde_json::Value {
        serde_json::json!({
            "status": self.status,
            "isValid": self.is_valid,
            "errorMessage": self.error_message,
            "code": self.code,
            "path": path,
        })
    }
}

pub fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    if path == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home);
        }
    }
    PathBuf::from(path)
}

pub fn validate_custom_binary(path: &str, expected: &str) -> Validation {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Validation::empty();
    }
    let expanded = expand_tilde(trimmed);
    let meta = match std::fs::metadata(&expanded) {
        Ok(m) => m,
        Err(_) => {
            return Validation {
                status: "fileNotFound",
                is_valid: false,
                error_message: Some("File does not exist at specified path".into()),
                code: Some("KUMA_ENV_FILE_NOT_FOUND"),
            }
        }
    };
    if meta.is_dir() {
        return Validation {
            status: "notExecutable",
            is_valid: false,
            error_message: Some("File is not an executable binary".into()),
            code: Some("KUMA_ENV_NOT_EXECUTABLE"),
        };
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if meta.permissions().mode() & 0o111 == 0 {
            return Validation {
                status: "notExecutable",
                is_valid: false,
                error_message: Some("File is not an executable binary".into()),
                code: Some("KUMA_ENV_NOT_EXECUTABLE"),
            };
        }
    }
    let name = expanded
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");
    if !name.to_ascii_lowercase().contains(&expected.to_ascii_lowercase()) {
        return Validation {
            status: "nameMismatch",
            is_valid: false,
            error_message: Some(format!(
                "Selected file '{name}' does not match expected '{expected}' binary"
            )),
            code: Some("KUMA_ENV_NAME_MISMATCH"),
        };
    }
    Validation::valid(expanded.display().to_string())
}

pub fn validate_kubeconfig_path(path: &str) -> Validation {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Validation::empty();
    }
    let expanded = expand_tilde(trimmed);
    if expanded.exists() {
        Validation::valid(expanded.display().to_string())
    } else {
        Validation {
            status: "fileNotFound",
            is_valid: false,
            error_message: Some("Configuration file does not exist at specified path".into()),
            code: Some("KUMA_ENV_KUBECONFIG_NOT_FOUND"),
        }
    }
}

pub fn strict_error_message(v: &Validation) -> String {
    v.error_message.clone().unwrap_or_else(|| {
        if v.status == "fileNotFound" {
            "File does not exist at specified path".into()
        } else {
            "Invalid path".into()
        }
    })
}

pub fn strict_kubeconfig_message() -> &'static str {
    "Selected kubeconfig file does not exist at specified path."
}
