use kuma_exec::check_port;

#[test]
fn dt_exe_ports_check_shape() {
    let v = check_port(65535);
    assert!(v.get("localPort").is_some());
    assert!(v.get("occupied").is_some());
}
