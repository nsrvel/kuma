use kuma_exec::{restart_service, start_shell, stop_service, ExecEngine};
use serde_json::json;

#[test]
fn shell_start_stop_echo() {
    let eng = ExecEngine::new();
    let sid = "00000000-0000-4000-8000-000000000099";
    let provider = json!({
        "type": "shell",
        "runCommand": "sleep 30",
    });
    start_shell(&eng, sid, &provider).unwrap();
    assert_eq!(eng.status_json(sid)["status"], "running");
    stop_service(&eng, sid).unwrap();
    assert_eq!(eng.status_json(sid)["status"], "stopped");
    restart_service(&eng, sid, &provider).unwrap();
    stop_service(&eng, sid).unwrap();
}
