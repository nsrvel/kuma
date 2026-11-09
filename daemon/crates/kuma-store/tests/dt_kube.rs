use kuma_store::{KubeConfigStore, StoreHandle};
use serde_json::json;

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

#[test]
fn dt_kube_test_connection_cached() {
    let (dir, kube) = open();
    let mut params = serde_json::Map::new();
    params.insert("id".into(), json!(kuma_store::kubeconfig::DEFAULT_ID));
    let a = kube.test_connection(&params).unwrap();
    let b = kube.test_connection(&params).unwrap();
    assert_eq!(a["verifiedAt"], b["verifiedAt"]);
    let _ = dir;
}
