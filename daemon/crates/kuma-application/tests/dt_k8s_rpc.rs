use kuma_application::{
    Application, ClientKind, DataCounts, DispatchContext, DispatchOutcome, LifecycleState,
};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::Request;
use kuma_protocol::methods;
use kuma_store::kubeconfig::DEFAULT_ID;
use kuma_store::StoreHandle;
use serde_json::{json, Map, Value};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

static KUBECTL_ENV: Mutex<()> = Mutex::new(());

fn lock_kubectl_env() -> std::sync::MutexGuard<'static, ()> {
    KUBECTL_ENV.lock().unwrap_or_else(|e| e.into_inner())
}

fn app_for(dir: &Path) -> (Arc<StoreHandle>, Application) {
    let store = Arc::new(StoreHandle::open(dir).unwrap());
    let app = Application::new(
        Arc::clone(&store),
        ExecEngine::new(),
        Arc::new(|| {}),
        LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000301".into()),
        DataCounts::empty(),
    );
    (store, app)
}

fn dispatch(
    app: &Application,
    method: &str,
    params: Value,
    id: i64,
) -> kuma_protocol::jsonrpc::Response {
    let req = Request {
        jsonrpc: "2.0".into(),
        method: method.into(),
        params,
        id: Some(id.into()),
    };
    let mut ctx = DispatchContext::unix(ClientKind::Cli);
    let DispatchOutcome::Reply(resp) = app.dispatch(req, &mut ctx) else {
        panic!("expected reply for {method}");
    };
    resp
}

fn write_script(dir: &Path, name: &str, body: &str) -> String {
    let path = dir.join(name);
    let mut f = fs::File::create(&path).unwrap();
    write!(f, "{body}").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    path.display().to_string()
}

fn set_kubeconfig_path(store: &StoreHandle, path: &Path) {
    let mut values = Map::new();
    values.insert(
        "kuma.settings.customKubeconfigPath".into(),
        json!(path.display().to_string()),
    );
    store.settings().set(&values, false, None).unwrap();
}

fn write_kube(dir: &Path, name: &str, current: &str, contexts: &[&str]) -> PathBuf {
    let path = dir.join(name);
    let mut body = format!("apiVersion: v1\nkind: Config\ncurrent-context: {current}\ncontexts:\n");
    for ctx in contexts {
        body.push_str(&format!("- name: {ctx}\n"));
    }
    body.push_str("# kuma-live-marker\n");
    fs::write(&path, body).unwrap();
    path
}

fn log_lines(path: &Path) -> Vec<String> {
    fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
}

fn kubeconfig_arg(line: &str) -> String {
    let parts: Vec<&str> = line.split_whitespace().collect();
    let idx = parts
        .iter()
        .position(|p| *p == "--kubeconfig")
        .unwrap_or_else(|| panic!("missing --kubeconfig in {line}"));
    parts[idx + 1].to_string()
}

#[test]
fn dt_k8s_namespaces_resources_fixture() {
    let _guard = lock_kubectl_env();
    let dir = tempfile::tempdir().unwrap();
    let bin = write_script(
        dir.path(),
        "mock-kubectl.sh",
        r#"#!/bin/sh
if [ "$1" = get ] && [ "$2" = namespaces ]; then
  echo namespace/default
  exit 0
fi
if [ "$1" = get ] && [ "$2" = pods ]; then
  echo pod/api
  exit 0
fi
exit 1
"#,
    );
    std::env::set_var("KUMA_KUBECTL_BIN", &bin);
    let (_store, app) = app_for(dir.path());
    let ns = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": DEFAULT_ID }),
        1,
    );
    let ns_body = ns.result.expect("namespaces result");
    assert_eq!(ns_body["namespaces"], json!(["default"]));
    let res = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({
            "kubeConfigID": DEFAULT_ID,
            "namespace": "default",
            "resourceType": "pod"
        }),
        2,
    );
    let res_body = res.result.expect("resources result");
    assert_eq!(res_body["names"], json!(["api"]));
    assert_eq!(res_body["resources"], res_body["names"]);
    std::env::remove_var("KUMA_KUBECTL_BIN");
}

#[test]
fn dt_k8s_live_discovery_uses_current_context_and_cache() {
    let _guard = lock_kubectl_env();
    let dir = tempfile::tempdir().unwrap();
    let log = dir.path().join("kubectl.log");
    let log_path = log.display().to_string();
    let bin = write_script(
        dir.path(),
        "live-kubectl.sh",
        &format!(
            r#"#!/bin/sh
LOG={log_path:?}
kube=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--kubeconfig" ]; then
    kube=$arg
  fi
  prev=$arg
done
if [ -z "$kube" ] || ! grep -q "kuma-live-marker" "$kube" 2>/dev/null; then
  echo "kubeconfig snapshot missing marker" >&2
  exit 4
fi
printf '%s\n' "$*" >> "$LOG"
case "$1 $2" in
  "get namespaces")
    printf '%s\n' "namespace/zeta" "namespace/alpha"
    exit 0
    ;;
  "get pods")
    printf '%s\n' "pod/web" "pod/api"
    exit 0
    ;;
  "get services")
    printf '%s\n' "service/db"
    exit 0
    ;;
  "get deployments")
    printf '%s\n' "deployment/worker"
    exit 0
    ;;
esac
echo "unexpected argv: $*" >&2
exit 2
"#
        ),
    );
    std::env::set_var("KUMA_KUBECTL_BIN", &bin);
    let source = write_kube(dir.path(), "dev.yaml", "dev", &["prod", "dev"]);
    let (store, app) = app_for(dir.path());
    set_kubeconfig_path(&store, &source);

    let ns = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": DEFAULT_ID }),
        1,
    );
    let body = ns.result.expect("namespaces");
    assert_eq!(body["namespaces"], json!(["alpha", "zeta"]));
    let first = log_lines(&log);
    assert_eq!(
        first.len(),
        1,
        "first list must call kubectl once: {first:?}"
    );
    assert!(first[0].contains("--context dev"), "{}", first[0]);
    assert!(first[0].contains("get namespaces -o name"), "{}", first[0]);
    let snap = kubeconfig_arg(&first[0]);
    assert_ne!(snap, source.display().to_string());

    let again = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": DEFAULT_ID }),
        2,
    );
    assert_eq!(
        again.result.unwrap()["namespaces"],
        json!(["alpha", "zeta"])
    );
    assert_eq!(
        log_lines(&log).len(),
        1,
        "repeat must hit the discovery cache"
    );

    let unknown = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": DEFAULT_ID, "context": "nope" }),
        3,
    );
    assert_eq!(
        unknown.result.unwrap()["namespaces"],
        json!(["alpha", "zeta"])
    );
    assert_eq!(
        log_lines(&log).len(),
        1,
        "unknown context resolves to current-context and stays cached"
    );

    let prod = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeconfigId": DEFAULT_ID, "context": "prod" }),
        4,
    );
    assert_eq!(prod.result.unwrap()["namespaces"], json!(["alpha", "zeta"]));
    let lines = log_lines(&log);
    assert_eq!(lines.len(), 2);
    assert!(lines[1].contains("--context prod"), "{}", lines[1]);

    let refreshed = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": DEFAULT_ID, "context": "prod", "refresh": true }),
        5,
    );
    assert_eq!(
        refreshed.result.unwrap()["namespaces"],
        json!(["alpha", "zeta"])
    );
    assert_eq!(
        log_lines(&log).len(),
        3,
        "refresh=true must bypass the cache"
    );

    let pods = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({
            "kubeConfigID": DEFAULT_ID,
            "namespace": "myns",
            "resourceType": "pod"
        }),
        6,
    );
    let pod_body = pods.result.expect("pods");
    assert_eq!(pod_body["names"], json!(["api", "web"]));
    assert_eq!(pod_body["resources"], pod_body["names"]);
    let lines = log_lines(&log);
    assert_eq!(lines.len(), 4);
    assert!(
        lines[3].contains("get pods --field-selector=status.phase=Running -o name"),
        "{}",
        lines[3]
    );
    assert!(lines[3].contains("-n myns"), "{}", lines[3]);
    assert!(lines[3].contains("--context dev"), "{}", lines[3]);

    let pods_again = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({
            "kubeConfigID": DEFAULT_ID,
            "namespace": "myns",
            "kind": "pod"
        }),
        7,
    );
    assert_eq!(pods_again.result.unwrap()["names"], json!(["api", "web"]));
    assert_eq!(log_lines(&log).len(), 4, "resource list must cache");

    let svcs = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({ "kubeConfigID": DEFAULT_ID, "resourceType": "service" }),
        8,
    );
    assert_eq!(svcs.result.unwrap()["names"], json!(["db"]));
    let lines = log_lines(&log);
    assert!(lines[4].contains("get services -o name"), "{}", lines[4]);
    assert!(
        !lines[4].contains("field-selector"),
        "services must not use the pod phase filter: {}",
        lines[4]
    );
    assert!(
        !lines[4].contains(" -n "),
        "blank namespace must omit -n: {}",
        lines[4]
    );

    let deps = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({ "kubeConfigID": DEFAULT_ID, "resourceType": "deployment" }),
        9,
    );
    assert_eq!(deps.result.unwrap()["names"], json!(["worker"]));

    let other = write_kube(dir.path(), "staging.yaml", "staging", &["staging"]);
    set_kubeconfig_path(&store, &other);
    let staged = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": DEFAULT_ID }),
        10,
    );
    assert_eq!(
        staged.result.unwrap()["namespaces"],
        json!(["alpha", "zeta"])
    );
    let lines = log_lines(&log);
    assert!(
        lines.last().unwrap().contains("--context staging"),
        "custom kubeconfig change must miss the cache and use the new current-context: {lines:?}"
    );

    std::env::remove_var("KUMA_KUBECTL_BIN");
}

#[test]
fn dt_k8s_discovery_cache_cleared_on_kubeconfig_update() {
    let _guard = lock_kubectl_env();
    let dir = tempfile::tempdir().unwrap();
    let log = dir.path().join("kubectl.log");
    let log_path = log.display().to_string();
    let bin = write_script(
        dir.path(),
        "live-kubectl.sh",
        &format!(
            r#"#!/bin/sh
LOG={log_path:?}
kube=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--kubeconfig" ]; then
    kube=$arg
  fi
  prev=$arg
done
if [ -z "$kube" ] || ! grep -q "kuma-live-marker" "$kube" 2>/dev/null; then
  echo "kubeconfig snapshot missing marker" >&2
  exit 4
fi
printf '%s\n' "$*" >> "$LOG"
echo namespace/team
exit 0
"#
        ),
    );
    std::env::set_var("KUMA_KUBECTL_BIN", &bin);
    let (store, app) = app_for(dir.path());
    let mut created = Map::new();
    created.insert("name".into(), json!("lab"));
    created.insert(
        "configContent".into(),
        json!("apiVersion: v1\nkind: Config\ncurrent-context: lab\ncontexts:\n- name: lab\n# kuma-live-marker\n"),
    );
    let row = store.kubeconfig().create(&created).unwrap();
    let id = row["kubeconfig"]["id"].as_str().unwrap().to_string();

    let first = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": id }),
        1,
    );
    assert_eq!(first.result.unwrap()["namespaces"], json!(["team"]));
    let second = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": id }),
        2,
    );
    assert_eq!(second.result.unwrap()["namespaces"], json!(["team"]));
    assert_eq!(log_lines(&log).len(), 1);

    let mut update = Map::new();
    update.insert("id".into(), json!(id));
    update.insert("name".into(), json!("lab-renamed"));
    store.kubeconfig().update(&update).unwrap();

    let third = dispatch(
        &app,
        methods::K8S_NAMESPACES,
        json!({ "kubeConfigID": id }),
        3,
    );
    assert_eq!(third.result.unwrap()["namespaces"], json!(["team"]));
    assert_eq!(
        log_lines(&log).len(),
        2,
        "kubeconfig update must drop the discovery cache even when YAML is unchanged"
    );
    std::env::remove_var("KUMA_KUBECTL_BIN");
}

#[test]
fn dt_k8s_discovery_errors_are_honest() {
    let _guard = lock_kubectl_env();
    let dir = tempfile::tempdir().unwrap();
    let bin = write_script(
        dir.path(),
        "fail-kubectl.sh",
        "#!/bin/sh\necho 'connection refused' >&2\nexit 1\n",
    );
    std::env::set_var("KUMA_KUBECTL_BIN", &bin);
    let (_store, app) = app_for(dir.path());

    let bad = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({ "resourceType": "cronjob" }),
        1,
    );
    let err = bad.error.expect("invalid enum");
    assert_eq!(err.data.unwrap()["kumaCode"], "KUMA_DAT_INVALID_ENUM");
    assert_eq!(err.message, "Invalid value 'cronjob' for resourceType");

    let ns = dispatch(&app, methods::K8S_NAMESPACES, json!({}), 2);
    let err = ns.error.expect("kubectl failure");
    assert_eq!(err.data.unwrap()["kumaCode"], "KUMA_K8S_KUBECTL_FAILED");
    assert_eq!(
        err.message,
        "Kubectl namespaces list error: connection refused"
    );

    let pods = dispatch(
        &app,
        methods::K8S_RESOURCES,
        json!({ "resourceType": "pod", "namespace": "default" }),
        3,
    );
    let err = pods.error.expect("pod discovery failure");
    assert_eq!(err.data.unwrap()["kumaCode"], "KUMA_K8S_KUBECTL_FAILED");
    assert_eq!(
        err.message,
        "Kubectl pods discovery error: connection refused"
    );

    std::env::set_var("KUMA_KUBECTL_BIN", "/no/such/kubectl");
    let missing = dispatch(&app, methods::K8S_NAMESPACES, json!({}), 4);
    let err = missing.error.expect("missing kubectl");
    assert_eq!(err.data.unwrap()["kumaCode"], "KUMA_K8S_KUBECTL_NOT_FOUND");
    assert_eq!(
        err.message,
        "Required binary 'kubectl' could not be located on this Mac."
    );
    std::env::remove_var("KUMA_KUBECTL_BIN");
}
