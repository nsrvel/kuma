//! Broad store API coverage (groups, kubeconfig, providers).

use kuma_store::kubeconfig::DEFAULT_ID;
use kuma_store::StoreHandle;
use serde_json::{json, Map};

#[test]
fn dt_store_group_kube_provider_depth() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let ws = store.workspace().list().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();

    let mut g1 = Map::new();
    g1.insert("workspaceID".into(), json!(ws));
    g1.insert("name".into(), json!("Depth A"));
    let ga = store.group().create(&g1).unwrap();
    let gid_a = ga["id"].as_str().unwrap();
    let mut g2 = Map::new();
    g2.insert("workspaceID".into(), json!(ws));
    g2.insert("name".into(), json!("Depth B"));
    let gb = store.group().create(&g2).unwrap();
    let gid_b = gb["id"].as_str().unwrap();
    store.group().list(&ws).unwrap();
    let mut upd = Map::new();
    upd.insert("id".into(), json!(gid_a));
    upd.insert("name".into(), json!("Depth A2"));
    store.group().update(&upd).unwrap();
    let groups = store.group().list(&ws).unwrap();
    let all_ids: Vec<_> = groups
        .iter()
        .filter_map(|g| g.get("id").and_then(|v| v.as_str()))
        .collect();
    let mut order = Map::new();
    order.insert("workspaceID".into(), json!(ws));
    order.insert("groupIDs".into(), json!(all_ids));
    store.group().reorder(&order).unwrap();
    store.group().delete(gid_b).unwrap();

    let klist = store.kubeconfig().list().unwrap();
    assert!(klist["kubeconfigs"]
        .as_array()
        .unwrap()
        .iter()
        .any(|k| k["id"] == DEFAULT_ID));
    store.kubeconfig().get(DEFAULT_ID, false).unwrap();
    store.kubeconfig().contexts(DEFAULT_ID).unwrap();

    let mut create = Map::new();
    create.insert("workspaceID".into(), json!(ws));
    create.insert("name".into(), json!("depth-svc"));
    let svc = store.service().create(&create).unwrap();
    let sid = svc["id"].as_str().unwrap();
    store.service().get(sid).unwrap();
    store
        .service()
        .list(&serde_json::Map::from_iter([(
            "workspaceID".into(),
            json!(ws),
        )]))
        .unwrap();
    let mut dup = Map::new();
    dup.insert("id".into(), json!(sid));
    store.service().duplicate(&dup).unwrap();
    let mut star = Map::new();
    star.insert("id".into(), json!(sid));
    star.insert("starred".into(), json!(true));
    store.service().set_starred(&star).unwrap();
    let mut dis = Map::new();
    dis.insert("id".into(), json!(sid));
    dis.insert("disabled".into(), json!(false));
    store.service().set_disabled(&dis).unwrap();
    let mut gr = Map::new();
    gr.insert("id".into(), json!(sid));
    gr.insert("groupIDs".into(), json!([]));
    store.service().set_groups(&gr).unwrap();
    let plist = store.provider().list(sid).unwrap();
    let pid = plist["providers"][0]["id"].as_str().unwrap();
    for (ptype, extra) in [
        ("shell", json!({"runCommand": "echo depth"})),
        ("httpCheck", json!({"httpCheckUrl": "http://127.0.0.1/"})),
        (
            "kubernetes",
            json!({"kubeConfigID": DEFAULT_ID, "kubeContext": "ctx", "targetName": "pod/x"}),
        ),
    ] {
        let mut add = Map::new();
        add.insert("serviceID".into(), json!(sid));
        let mut prov = Map::new();
        prov.insert("type".into(), json!(ptype));
        prov.insert("label".into(), json!(format!("{ptype}-label")));
        if let Some(obj) = extra.as_object() {
            for (k, v) in obj {
                prov.insert(k.clone(), v.clone());
            }
        }
        add.insert("provider".into(), json!(prov));
        store.provider().add(&add).unwrap();
    }
    store.provider().get(pid).unwrap();
    let providers = store.provider().list(sid).unwrap();
    let k8s_pid = providers["providers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["type"] == "kubernetes")
        .and_then(|p| p["id"].as_str())
        .unwrap();
    let mut sw = Map::new();
    sw.insert("id".into(), json!(sid));
    sw.insert("providerID".into(), json!(k8s_pid));
    store.service().switch_provider(&sw).unwrap();
    let mut ports = Map::new();
    ports.insert("serviceID".into(), json!(sid));
    ports.insert("providerID".into(), json!(k8s_pid));
    ports.insert(
        "ports".into(),
        json!([{"localPort": 19090, "remotePort": 9090}]),
    );
    store.provider().set_ports(&ports).unwrap();
    let mut pre = Map::new();
    pre.insert("id".into(), json!(sid));
    let pf = store.service().preflight(&pre).unwrap();
    assert!(pf.get("ok").is_some());
}
