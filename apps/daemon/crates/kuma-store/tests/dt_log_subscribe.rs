use kuma_store::LogBuffer;

#[test]
fn dt_log_subscribe_receives_append() {
    let buf = LogBuffer::new();
    let rx = buf.subscribe("00000000-0000-0000-0000-000000000099");
    buf.append("00000000-0000-0000-0000-000000000099", "alpha");
    assert_eq!(rx.recv().unwrap(), "alpha");
}
