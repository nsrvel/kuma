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
