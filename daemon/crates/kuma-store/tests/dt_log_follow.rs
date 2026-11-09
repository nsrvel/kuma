use kuma_store::StoreHandle;

#[test]
fn dt_log_follow_subscription_id() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let sid = "00000000-0000-4000-8000-000000000401";
    store.logs().append(sid, "line-a");
    let snap = store.logs().start_follow(sid);
    assert_eq!(snap["following"], true);
    let sub = snap["subscriptionId"].as_str().unwrap();
    assert_eq!(
        store.logs().follow_service_for_sub(sub),
        Some(sid.to_string())
    );
    assert!(store.logs().end_follow(sub));
}
