use kuma_store::Vault;
use tempfile::TempDir;

#[test]
fn dt_sec_roundtrip_aes_gcm_wire() {
    let dir = TempDir::new().unwrap();
    let vault = Vault::open(dir.path()).unwrap();
    let plain = "kuma-secret-value";
    let enc = vault.encrypt_field(plain).unwrap();
    assert!(enc.contains(':'));
    assert!(!enc.starts_with("kuma:v1:"));
    let dec = vault.decrypt_field(&enc).unwrap();
    assert_eq!(dec, plain);
}
