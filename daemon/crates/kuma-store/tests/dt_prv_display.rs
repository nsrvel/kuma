use kuma_store::{display_name, extract_compose_image};
use serde_json::json;

#[test]
fn dt_prv_03_display_k8s_target() {
    let p = json!({ "type": "kubernetes", "targetName": "  api-0 " });
    assert_eq!(display_name(&p, "svc"), "k8s: api-0");
}

#[test]
fn dt_prv_04_extract_compose_image() {
    let p = json!({
        "type": "docker",
        "yamlConfig": "services:\n  redis:\n    image: docker.io/library/redis:7\n"
    });
    assert_eq!(extract_compose_image(&p).as_deref(), Some("redis:7"));
}
