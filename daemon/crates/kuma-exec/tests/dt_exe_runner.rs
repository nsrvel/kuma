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

fn assert_start_err(provider: serde_json::Value, needle: &str) {
    let eng = Arc::new(ExecEngine::new());
    let sid = "00000000-0000-4000-8000-0000000000ae";
    let err = start_service(&eng, sid, &provider).unwrap_err().to_string();
    assert!(err.contains(needle), "err={err}");
}

#[test]
fn dt_exe_required_fields_matrix() {
    assert_start_err(json!({"type": "shell"}), "runCommand");
    assert_start_err(json!({"type": "ssh"}), "sshHost");
    assert_start_err(json!({"type": "tunnel"}), "tunnelTargetUrl");
    assert_start_err(json!({"type": "httpCheck"}), "httpCheckUrl");
    assert_start_err(json!({"type": "processMonitor"}), "monitorProcessName");
}

#[test]
fn dt_exe_more_provider_run_commands() {
    let eng = Arc::new(ExecEngine::new());
    let cases = [
        (
            "00000000-0000-4000-8000-0000000000b1",
            json!({"type": "httpCheck", "httpCheckUrl": "http://127.0.0.1", "httpCheckInterval": 3600}),
        ),
        (
            "00000000-0000-4000-8000-0000000000b2",
            json!({"type": "processMonitor", "monitorProcessName": "sleep", "monitorInterval": 3600}),
        ),
    ];
    for (sid, provider) in cases {
        start_service(&eng, sid, &provider).unwrap();
        stop_service(&eng, sid).unwrap();
    }
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
