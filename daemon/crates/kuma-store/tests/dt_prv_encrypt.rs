use kuma_store::StoreHandle;
use serde_json::json;
use tempfile::TempDir;

#[test]
fn dt_prv_ssh_password_encrypted_at_rest() {
    let dir = TempDir::new().unwrap();
    let store = StoreHandle::open(dir.path()).expect("open store");
    let vault = store.vault();
    let svc = store
        .service()
        .create(
            &serde_json::from_value(json!({
                "workspaceID": store
                    .workspace()
                    .list()
                    .unwrap()
                    .first()
                    .and_then(|w| w.get("id"))
                    .and_then(|v| v.as_str())
                    .expect("seed workspace"),
                "name": "enc-test",
            }))
            .unwrap(),
        )
        .expect("create service");
    let sid = svc
        .get("id")
        .or_else(|| svc.get("serviceID"))
        .and_then(|v| v.as_str())
        .unwrap();
    let plist = store.provider().list(sid).unwrap();
    let pid = plist
        .get("providers")
        .and_then(|v| v.as_array())
        .and_then(|a| a.first())
        .and_then(|p| p.get("id"))
        .and_then(|v| v.as_str())
        .unwrap();
    store
        .provider()
        .update(
            vault,
            &serde_json::from_value(json!({
                "id": pid,
                "sshPassword": "hunter2",
            }))
            .unwrap(),
        )
        .expect("update");
    let raw: String = {
        let conn = store.kuma_connection();
        let guard = conn.lock().unwrap();
        guard
            .query_row(
                "SELECT sshPassword FROM provider WHERE id = ?1",
                [pid],
                |r| r.get(0),
            )
            .unwrap()
    };
    assert_ne!(raw, "hunter2");
    assert!(raw.contains(':'));
    let exec = store.provider().get_for_exec(pid, vault).unwrap();
    assert_eq!(
        exec.get("sshPassword").and_then(|v| v.as_str()),
        Some("hunter2")
    );
}
