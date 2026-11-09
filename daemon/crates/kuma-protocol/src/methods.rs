//! RPC method names from docs/specs/daemon/00-overview-and-conventions.md §5.

pub const DAEMON_PING: &str = "daemon.ping";
pub const DAEMON_STATUS: &str = "daemon.status";
pub const DAEMON_SHUTDOWN: &str = "daemon.shutdown";
pub const DAEMON_ROTATE_API_TOKEN: &str = "daemon.rotate_api_token";

pub const SETTINGS_LIST: &str = "settings.list";
pub const SETTINGS_GET: &str = "settings.get";
pub const SETTINGS_SET: &str = "settings.set";
pub const SETTINGS_RESET: &str = "settings.reset";

pub const ENV_PATH: &str = "env.path";
pub const ENV_RESOLVE_EXECUTABLE: &str = "env.resolve_executable";
pub const ENV_VALIDATE_BINARY: &str = "env.validate_binary";
pub const ENV_DEPENDENCIES: &str = "env.dependencies";
pub const ENV_REFRESH: &str = "env.refresh";

pub const WORKSPACE_LIST: &str = "workspace.list";
pub const WORKSPACE_GET: &str = "workspace.get";
pub const WORKSPACE_CREATE: &str = "workspace.create";
pub const WORKSPACE_UPDATE: &str = "workspace.update";
pub const WORKSPACE_DELETE: &str = "workspace.delete";
pub const WORKSPACE_REORDER: &str = "workspace.reorder";
pub const WORKSPACE_SET_IMAGE: &str = "workspace.set_image";
pub const WORKSPACE_CLEAR_IMAGE: &str = "workspace.clear_image";
pub const WORKSPACE_GET_IMAGE: &str = "workspace.get_image";

pub const GROUP_LIST: &str = "group.list";
pub const GROUP_CREATE: &str = "group.create";
pub const GROUP_UPDATE: &str = "group.update";
pub const GROUP_DELETE: &str = "group.delete";
pub const GROUP_REORDER: &str = "group.reorder";

pub const SERVICE_LIST: &str = "service.list";
pub const SERVICE_GET: &str = "service.get";
pub const SERVICE_CREATE: &str = "service.create";
pub const SERVICE_UPDATE: &str = "service.update";
pub const SERVICE_DELETE: &str = "service.delete";
pub const SERVICE_DUPLICATE: &str = "service.duplicate";
pub const SERVICE_SET_STARRED: &str = "service.set_starred";
pub const SERVICE_SET_DISABLED: &str = "service.set_disabled";
pub const SERVICE_SET_GROUPS: &str = "service.set_groups";
pub const SERVICE_TOGGLE_GROUP: &str = "service.toggle_group";
pub const SERVICE_SWITCH_PROVIDER: &str = "service.switch_provider";

pub const PROVIDER_LIST: &str = "provider.list";
pub const PROVIDER_ADD: &str = "provider.add";
pub const PROVIDER_UPDATE: &str = "provider.update";
pub const PROVIDER_DELETE: &str = "provider.delete";
pub const PROVIDER_SET_PORTS: &str = "provider.set_ports";

pub const SERVICE_PREFLIGHT: &str = "service.preflight";
pub const SERVICE_START: &str = "service.start";
pub const SERVICE_STOP: &str = "service.stop";
pub const SERVICE_RESTART: &str = "service.restart";
pub const SERVICE_START_ALL: &str = "service.start_all";
pub const SERVICE_STOP_ALL: &str = "service.stop_all";
pub const SERVICE_STATUS: &str = "service.status";
pub const SERVICE_STATUSES: &str = "service.statuses";
pub const PORTS_CHECK: &str = "ports.check";
pub const RUNTIME_ADOPT_REPORT: &str = "runtime.adopt_report";

pub const KUBECONFIG_LIST: &str = "kubeconfig.list";
pub const KUBECONFIG_GET: &str = "kubeconfig.get";
pub const KUBECONFIG_CREATE: &str = "kubeconfig.create";
pub const KUBECONFIG_UPDATE: &str = "kubeconfig.update";
pub const KUBECONFIG_DELETE: &str = "kubeconfig.delete";
pub const KUBECONFIG_CONTEXTS: &str = "kubeconfig.contexts";
pub const KUBECONFIG_TEST_CONNECTION: &str = "kubeconfig.test_connection";

pub const K8S_RESOLVE_TARGET: &str = "k8s.resolve_target";
pub const K8S_NAMESPACES: &str = "k8s.namespaces";
pub const K8S_RESOURCES: &str = "k8s.resources";

pub const LOGS_TAIL: &str = "logs.tail";
pub const LOGS_CLEAR: &str = "logs.clear";
pub const LOGS_WORKLOAD_TAIL: &str = "logs.workload_tail";
pub const EVENTS_SUBSCRIBE: &str = "events.subscribe";
pub const EVENTS_UNSUBSCRIBE: &str = "events.unsubscribe";
pub const LOGS_FOLLOW: &str = "logs.follow";

pub const DATA_EXPORT: &str = "data.export";
pub const DATA_EXPORT_SERVICE_JSON: &str = "data.export_service_json";
pub const DATA_IMPORT_PREVIEW: &str = "data.import_preview";
pub const DATA_IMPORT: &str = "data.import";
pub const DATA_FACTORY_RESET: &str = "data.factory_reset";

/// All registered method names (00 §5.1–5.6).
pub const ALL: &[&str] = &[
    DAEMON_PING,
    DAEMON_STATUS,
    DAEMON_SHUTDOWN,
    DAEMON_ROTATE_API_TOKEN,
    SETTINGS_LIST,
    SETTINGS_GET,
    SETTINGS_SET,
    SETTINGS_RESET,
    ENV_PATH,
    ENV_RESOLVE_EXECUTABLE,
    ENV_VALIDATE_BINARY,
    ENV_DEPENDENCIES,
    ENV_REFRESH,
    WORKSPACE_LIST,
    WORKSPACE_GET,
    WORKSPACE_CREATE,
    WORKSPACE_UPDATE,
    WORKSPACE_DELETE,
    WORKSPACE_REORDER,
    WORKSPACE_SET_IMAGE,
    WORKSPACE_CLEAR_IMAGE,
    WORKSPACE_GET_IMAGE,
    GROUP_LIST,
    GROUP_CREATE,
    GROUP_UPDATE,
    GROUP_DELETE,
    GROUP_REORDER,
    SERVICE_LIST,
    SERVICE_GET,
    SERVICE_CREATE,
    SERVICE_UPDATE,
    SERVICE_DELETE,
    SERVICE_DUPLICATE,
    SERVICE_SET_STARRED,
    SERVICE_SET_DISABLED,
    SERVICE_SET_GROUPS,
    SERVICE_TOGGLE_GROUP,
    SERVICE_SWITCH_PROVIDER,
    PROVIDER_LIST,
    PROVIDER_ADD,
    PROVIDER_UPDATE,
    PROVIDER_DELETE,
    PROVIDER_SET_PORTS,
    SERVICE_PREFLIGHT,
    SERVICE_START,
    SERVICE_STOP,
    SERVICE_RESTART,
    SERVICE_START_ALL,
    SERVICE_STOP_ALL,
    SERVICE_STATUS,
    SERVICE_STATUSES,
    PORTS_CHECK,
    RUNTIME_ADOPT_REPORT,
    KUBECONFIG_LIST,
    KUBECONFIG_GET,
    KUBECONFIG_CREATE,
    KUBECONFIG_UPDATE,
    KUBECONFIG_DELETE,
    KUBECONFIG_CONTEXTS,
    KUBECONFIG_TEST_CONNECTION,
    K8S_RESOLVE_TARGET,
    K8S_NAMESPACES,
    K8S_RESOURCES,
    LOGS_TAIL,
    LOGS_CLEAR,
    LOGS_WORKLOAD_TAIL,
    EVENTS_SUBSCRIBE,
    EVENTS_UNSUBSCRIBE,
    LOGS_FOLLOW,
    DATA_EXPORT,
    DATA_EXPORT_SERVICE_JSON,
    DATA_IMPORT_PREVIEW,
    DATA_IMPORT,
    DATA_FACTORY_RESET,
];

pub fn all_method_names() -> Vec<&'static str> {
    ALL.to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_has_74_methods() {
        assert_eq!(ALL.len(), 74);
    }
}
