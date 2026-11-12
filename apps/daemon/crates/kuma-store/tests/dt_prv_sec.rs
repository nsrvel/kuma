use kuma_store::{StoreHandle, Vault};
use tempfile::TempDir;

#[test]
fn dt_prv_ssh_password_encrypt_at_rest() {
    let dir = TempDir::new().unwrap();
    let store = StoreHandle::open(dir.path()).unwrap();
    let vault = Vault::open(dir.path()).unwrap();
    let enc = vault.encrypt_field("sekrit").unwrap();
    assert!(enc.contains(':'));
    let dec = vault.decrypt_field(&enc).unwrap();
    assert_eq!(dec, "sekrit");
    let _ = store;
}
