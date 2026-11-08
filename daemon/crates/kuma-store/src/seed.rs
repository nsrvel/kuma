use chrono::{DateTime, Utc};
use uuid::Uuid;

/// GRDB-style UTC timestamp for `kuma.sqlite` ([01 §3.4.2](docs/specs/daemon/01-data-model.md)).
pub fn format_grdb_datetime(dt: DateTime<Utc>) -> String {
    dt.format("%Y-%m-%d %H:%M:%S%.3f").to_string()
}

pub fn now_grdb_datetime() -> String {
    format_grdb_datetime(Utc::now())
}

pub fn new_uppercase_uuid() -> String {
    Uuid::new_v4().to_string().to_uppercase()
}

/// Default workspace name ([01 §3.8](docs/specs/daemon/01-data-model.md)).
pub fn default_workspace_name() -> String {
    let display = default_user_display_name();
    let word = display.split_whitespace().next().unwrap_or("User");
    let mut chars = word.chars();
    let Some(first) = chars.next() else {
        return "User's Space".to_string();
    };
    let rest: String = chars.collect();
    format!(
        "{}{rest}'s Space",
        first.to_uppercase().collect::<String>()
    )
}

fn default_user_display_name() -> String {
    #[cfg(unix)]
    {
        use std::ffi::CStr;
        unsafe {
            let uid = libc::getuid();
            let mut pwd: libc::passwd = std::mem::zeroed();
            let mut buf = [0u8; 8192];
            let mut result: *mut libc::passwd = std::ptr::null_mut();
            if libc::getpwuid_r(uid, &mut pwd, buf.as_mut_ptr() as *mut _, buf.len(), &mut result)
                == 0
                && !result.is_null()
            {
                let gecos = CStr::from_ptr(pwd.pw_gecos).to_string_lossy();
                let name_part = gecos.split(',').next().unwrap_or("").trim();
                if !name_part.is_empty() {
                    return name_part.to_string();
                }
                return CStr::from_ptr(pwd.pw_name).to_string_lossy().into_owned();
            }
        }
    }
    std::env::var("USER")
        .or_else(|_| std::env::var("LOGNAME"))
        .unwrap_or_else(|_| "User".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamp_has_millis() {
        let s = format_grdb_datetime(Utc::now());
        assert!(regex_like(&s));
    }

    fn regex_like(s: &str) -> bool {
        s.len() >= 23
            && s.as_bytes().get(4) == Some(&b'-')
            && s.as_bytes().get(7) == Some(&b'-')
            && s.contains('.')
    }

    #[test]
    fn default_name_ends_with_space_suffix() {
        let n = default_workspace_name();
        assert!(n.ends_with("'s Space"));
    }
}
