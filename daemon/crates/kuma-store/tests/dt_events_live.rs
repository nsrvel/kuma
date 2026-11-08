use kuma_store::StoreHandle;
use std::thread;
use std::time::Duration;

#[test]
fn dt_events_live_subscribe_receives_publish() {
    let dir = tempfile::tempdir().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let rx = store.events().live_subscribe();
    let bus = store.events().clone();
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(50));
        let _ = bus.publish(
            "settings.changed",
            serde_json::json!({ "key": "autoResume" }),
        );
    });
    let line = rx.recv_timeout(Duration::from_secs(2)).expect("live event");
    assert!(line.contains("settings.changed"));
}
