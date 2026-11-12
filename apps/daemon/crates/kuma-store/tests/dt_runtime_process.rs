use kuma_store::StoreHandle;

#[test]
fn dt_runtime_process_upsert_and_clear() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let sid = "00000000-0000-4000-8000-000000000501";
    store
        .runtime_process()
        .upsert_running(sid, std::process::id())
        .unwrap();
    let rows = store.runtime_process().adopt_candidates().unwrap();
    assert!(rows.iter().any(|(s, _)| s == sid));
    store.runtime_process().mark_intentional_stop(sid).unwrap();
    assert!(store
        .runtime_process()
        .adopt_candidates()
        .unwrap()
        .iter()
        .all(|(s, _)| s != sid));
    store.runtime_process().delete_row(sid).unwrap();
}
