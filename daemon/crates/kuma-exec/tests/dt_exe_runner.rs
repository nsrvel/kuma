use kuma_exec::{start_service, stop_service, ExecEngine};
use serde_json::json;
use std::sync::Arc;

#[test]
fn dt_exe_unknown_provider_type() {
    let eng = Arc::new(ExecEngine::new());
    let err = start_service(
        &eng,
        "00000000-0000-4000-8000-0000000000ab",
        &json!({"type": "bogus"}),
    )
    .unwrap_err()
    .to_string();
    assert!(err.contains("unknown provider"));
}

#[test]
fn dt_exe_kubernetes_run_command_path() {
    let eng = Arc::new(ExecEngine::new());
    let sid = "00000000-0000-4000-8000-0000000000ac";
    let provider = json!({
        "type": "kubernetes",
        "runCommand": "sleep 25",
    });
    start_service(&eng, sid, &provider).unwrap();
    assert_eq!(eng.status_json(sid)["status"], "running");
    stop_service(&eng, sid).unwrap();
}

#[test]
fn dt_exe_docker_run_command_avoids_compose_up() {
    let eng = Arc::new(ExecEngine::new());
    let sid = "00000000-0000-4000-8000-0000000000ad";
    let provider = json!({
        "type": "docker",
        "runCommand": "sleep 25",
    });
    start_service(&eng, sid, &provider).unwrap();
    stop_service(&eng, sid).unwrap();
}
