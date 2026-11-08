use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use getrandom::getrandom;
use kuma_domain::StoreError;
use std::path::{Path, PathBuf};

const LEGACY_XOR_PREFIX: &str = "kuma:v1:";

#[derive(Clone)]
pub struct Vault {
    path: PathBuf,
}

impl Vault {
    pub fn open(data_dir: &Path) -> Result<Self, StoreError> {
        let path = data_dir.join("master.key");
        if !path.exists() {
            let key = random_32()?;
            write_key(&path, &key)?;
        }
        Ok(Self { path })
    }

    pub fn encrypt_field(&self, plain: &str) -> Result<String, StoreError> {
        if plain.is_empty() {
            return Ok(String::new());
        }
        let key = read_key(&self.path)?;
        aes_gcm_encrypt(&key, plain.as_bytes())
    }

    pub fn decrypt_field(&self, stored: &str) -> Result<String, StoreError> {
        if stored.is_empty() {
            return Ok(String::new());
        }
        if let Some(hex_part) = stored.strip_prefix(LEGACY_XOR_PREFIX) {
            let key = read_key(&self.path)?;
            let raw = hex::decode(hex_part).map_err(|e| StoreError::RowDecode {
                table: "vault".into(),
                column: e.to_string(),
            })?;
            let plain = xor_stream(&key, &raw)?;
            return String::from_utf8(plain).map_err(|e| StoreError::RowDecode {
                table: "vault".into(),
                column: e.to_string(),
            });
        }
        let key = read_key(&self.path)?;
        let plain = aes_gcm_decrypt(&key, stored)?;
        String::from_utf8(plain).map_err(|e| StoreError::RowDecode {
            table: "vault".into(),
            column: e.to_string(),
        })
    }

    pub fn redact_secret(value: &str) -> bool {
        !value.is_empty()
    }
}

fn random_32() -> Result<Vec<u8>, StoreError> {
    let mut buf = [0u8; 32];
    getrandom(&mut buf).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    Ok(buf.to_vec())
}

fn write_key(path: &Path, key: &[u8]) -> Result<(), StoreError> {
    std::fs::write(path, key).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    set_mode(path, 0o600)
}

fn read_key(path: &Path) -> Result<Vec<u8>, StoreError> {
    let data = std::fs::read(path).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    if data.len() != 32 {
        return Err(StoreError::DbOpenFailed {
            detail: format!("master.key length {}", data.len()),
        });
    }
    Ok(data)
}

fn aes_gcm_encrypt(key: &[u8], plain: &[u8]) -> Result<String, StoreError> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| StoreError::RowDecode {
        table: "vault".into(),
        column: e.to_string(),
    })?;
    let mut nonce_bytes = [0u8; 12];
    getrandom(&mut nonce_bytes).map_err(|e| StoreError::DbOpenFailed {
        detail: e.to_string(),
    })?;
    let nonce = Nonce::from_slice(&nonce_bytes);
    let encrypted = cipher.encrypt(nonce, plain).map_err(|e| StoreError::RowDecode {
        table: "vault".into(),
        column: e.to_string(),
    })?;
    if encrypted.len() < 16 {
        return Err(StoreError::RowDecode {
            table: "vault".into(),
            column: "ciphertext too short".into(),
        });
    }
    let tag_start = encrypted.len() - 16;
    let (ct, tag) = encrypted.split_at(tag_start);
    Ok(format!(
        "{}:{}:{}",
        STANDARD.encode(nonce_bytes),
        STANDARD.encode(tag),
        STANDARD.encode(ct)
    ))
}

fn aes_gcm_decrypt(key: &[u8], stored: &str) -> Result<Vec<u8>, StoreError> {
    let trimmed = stored.trim();
    let parts: Vec<&str> = trimmed.split(':').collect();
    if parts.len() != 3 {
        return Ok(trimmed.as_bytes().to_vec());
    }
    let nonce = STANDARD.decode(parts[0]).map_err(|e| StoreError::RowDecode {
        table: "vault".into(),
        column: e.to_string(),
    })?;
    let tag = STANDARD.decode(parts[1]).map_err(|e| StoreError::RowDecode {
        table: "vault".into(),
        column: e.to_string(),
    })?;
    let body = STANDARD.decode(parts[2]).map_err(|e| StoreError::RowDecode {
        table: "vault".into(),
        column: e.to_string(),
    })?;
    if nonce.len() != 12 {
        return Err(StoreError::RowDecode {
            table: "vault".into(),
            column: "bad nonce length".into(),
        });
    }
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| StoreError::RowDecode {
        table: "vault".into(),
        column: e.to_string(),
    })?;
    if tag.len() != 16 {
        return Err(StoreError::RowDecode {
            table: "vault".into(),
            column: "bad tag length".into(),
        });
    }
    let nonce = Nonce::from_slice(&nonce);
    let mut payload = body;
    payload.extend_from_slice(&tag);
    cipher
        .decrypt(nonce, payload.as_ref())
        .map_err(|e| StoreError::RowDecode {
            table: "vault".into(),
            column: e.to_string(),
        })
}

fn xor_stream(key: &[u8], cipher: &[u8]) -> Result<Vec<u8>, StoreError> {
    let mut out = cipher.to_vec();
    for (i, b) in out.iter_mut().enumerate() {
        *b ^= key[i % key.len()];
    }
    Ok(out)
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) -> Result<(), StoreError> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode)).map_err(|e| {
        StoreError::DbOpenFailed {
            detail: e.to_string(),
        }
    })
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) -> Result<(), StoreError> {
    Ok(())
}

mod hex {
    use kuma_domain::StoreError;

    pub fn decode(s: &str) -> Result<Vec<u8>, StoreError> {
        if !s.len().is_multiple_of(2) {
            return Err(StoreError::RowDecode {
                table: "vault".into(),
                column: "hex".into(),
            });
        }
        (0..s.len())
            .step_by(2)
            .map(|i| {
                u8::from_str_radix(&s[i..i + 2], 16).map_err(|e| StoreError::RowDecode {
                    table: "vault".into(),
                    column: e.to_string(),
                })
            })
            .collect()
    }
}
