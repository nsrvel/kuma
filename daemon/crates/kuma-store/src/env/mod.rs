mod dependencies;
mod path;
mod resolve;

pub use dependencies::validate_binary;
pub use path::{PathCache, PathResolver};
use crate::SettingsStore;
use serde_json::{json, Value};
use std::sync::Arc;

#[derive(Clone)]
pub struct EnvService {
    settings: SettingsStore,
    paths: Arc<PathResolver>,
}

impl EnvService {
    pub fn new(settings: SettingsStore) -> Self {
        Self {
            settings,
            paths: Arc::new(PathResolver::new()),
        }
    }

    pub fn path(&self, refresh: bool) -> PathCache {
        self.paths.resolve(refresh)
    }

    pub fn path_json(&self, refresh: bool) -> Value {
        let c = self.path(refresh);
        json!({
            "path": c.path,
            "directories": c.directories,
            "shell": c.shell,
            "customPaths": [],
            "cached": c.cached,
        })
    }

    pub fn refresh(&self) -> Value {
        self.paths.invalidate();
        self.path_json(false)
    }

    pub fn resolve(&self, command: &str, custom_path: Option<&str>, apply_settings: bool) -> Value {
        resolve::resolve_executable(command, custom_path, apply_settings, &self.settings, &self.paths)
    }

    pub fn dependencies(&self) -> Value {
        dependencies::dependencies(&self.settings, &self.paths)
    }

    pub fn validate(&self, path: &str, expected: &str) -> Value {
        validate_binary(path, expected)
    }
}
