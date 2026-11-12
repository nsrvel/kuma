use kuma_store::{KubeConfigStore, StoreHandle};
use serde_json::json;
use std::fs;
use std::io::Write;

fn open() -> (tempfile::TempDir, KubeConfigStore) {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let kube = store.kubeconfig().clone();
    (dir, kube)
}

#[test]
fn dt_dat_31_default_listed_first() {
    let (_d, kube) = open();
    let list = kube.list().unwrap();
    let items = list["kubeconfigs"].as_array().unwrap();
    assert_eq!(items[0]["id"], json!(kuma_store::kubeconfig::DEFAULT_ID));
    assert_eq!(items[0]["isDefault"], true);
}

#[test]
fn dt_k8s_default_immutable() {
    let (_d, kube) = open();
    assert!(kube.delete(kuma_store::kubeconfig::DEFAULT_ID).is_err());
}

#[test]
fn dt_k8s_resolve_target_parser() {
    let v = kuma_store::resolve_k8s_target("pod/redis", true);
    assert_eq!(v["kubectlReference"], "pod/redis");
}

fn mock_kubectl(dir: &tempfile::TempDir) -> String {
    let path = dir.path().join("mock-kubectl.sh");
    let mut f = fs::File::create(&path).unwrap();
    writeln!(
        f,
        "#!/bin/sh\nif [ \"$1\" = version ]; then echo clientVersion: ok; exit 0; fi\nexit 1"
    )
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }
    path.display().to_string()
}

#[test]
fn dt_kube_test_connection_cached() {
    let (dir, kube) = open();
    std::env::set_var("KUMA_KUBECTL_BIN", mock_kubectl(&dir));
    let mut params = serde_json::Map::new();
    params.insert("id".into(), json!(kuma_store::kubeconfig::DEFAULT_ID));
    let a = kube.test_connection(&params).unwrap();
    let b = kube.test_connection(&params).unwrap();
    assert_eq!(a["verifiedAt"], b["verifiedAt"]);
    std::env::remove_var("KUMA_KUBECTL_BIN");
}
