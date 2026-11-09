use kuma_store::StoreHandle;
use serde_json::json;

#[test]
fn events_subscribe_replays_settings_changed() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let bus = store.events();
    let sub = bus.subscribe(vec!["settings.changed".into()]);
    bus.publish(
        "settings.changed",
        json!({ "reason": "set", "keys": ["demo"] }),
    )
    .unwrap();
    let (events, _, _) = bus.replay(0, Some(&["settings.changed".to_string()]));
    assert_eq!(events.len(), 1);
    assert_eq!(events[0]["name"], "settings.changed");
    assert!(bus.unsubscribe(&sub));

    let (_rec, recorded) =
        kuma_store::SettingsStore::with_recording_sink(store.settings().connection());
    let _ = _rec
        .set(
            &serde_json::Map::from_iter([("kuma.settings.appearance".into(), json!("light"))]),
            false,
            None,
        )
        .unwrap();
    let recorded = recorded.lock().unwrap();
    assert!(!recorded.is_empty());
}
