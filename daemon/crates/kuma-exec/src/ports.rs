use serde_json::{json, Value};

pub fn check_port(local_port: u16) -> Value {
    let occupied = std::net::TcpListener::bind(("127.0.0.1", local_port)).is_err();
    json!({
        "localPort": local_port,
        "occupied": occupied,
        "policy": if occupied { "warn_and_block" } else { "allow" },
    })
}
