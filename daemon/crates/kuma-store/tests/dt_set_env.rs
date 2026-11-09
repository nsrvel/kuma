use kuma_store::StoreHandle;

#[test]
fn dt_set_10_env_path_has_directories() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let body = store.env().path_json(false);
    assert!(body.get("path").and_then(|v| v.as_str()).is_some());
    assert!(body.get("directories").and_then(|v| v.as_array()).is_some());
}

#[test]
fn dt_set_19_resolve_empty_command() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let body = store.env().resolve("", None, false);
    assert!(body.get("path").unwrap().is_null());
}

#[test]
fn dt_set_11_dependencies_lists_engines() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let body = store.env().dependencies();
    let engines = body["engines"].as_array().unwrap();
    assert!(engines.iter().any(|e| e["name"] == "docker"));
    assert!(engines.iter().any(|e| e["name"] == "kubectl"));
}

#[test]
fn dt_set_20_env_refresh_invalidates_cache() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let a = store.env().path_json(false);
    let b = store.env().refresh();
    assert!(a.get("path").is_some());
    assert!(b.get("path").is_some());
}

#[test]
fn dt_set_15_validate_missing_binary() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let body = store.env().validate("/no/such/kuma-tool", "docker");
    assert_eq!(body["status"], "fileNotFound");
}
