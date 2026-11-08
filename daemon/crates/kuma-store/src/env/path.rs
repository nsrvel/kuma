use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Mutex;

const SNIFF_BOOTSTRAP: &str = r#"[ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; echo $PATH"#;

const FALLBACK: &[&str] = &[
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
];

#[derive(Clone)]
pub struct PathCache {
    pub path: String,
    pub directories: Vec<serde_json::Value>,
    pub shell: String,
    pub cached: bool,
}

pub struct PathResolver {
  inner: Mutex<Option<PathCache>>,
}

impl PathResolver {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(None),
        }
    }

    pub fn resolve(&self, refresh: bool) -> PathCache {
        let mut guard = self.inner.lock().unwrap();
        if !refresh {
            if let Some(c) = guard.as_ref() {
                let mut out = c.clone();
                out.cached = true;
                return out;
            }
        }
        let computed = compute_path();
        *guard = Some(computed.clone());
        computed
    }

    pub fn invalidate(&self) {
        *self.inner.lock().unwrap() = None;
    }
}

fn home() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/"))
}

fn sniff_path() -> Option<String> {
    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
    let shell = if is_executable(&shell) {
        shell
    } else {
        "/bin/zsh".into()
    };
    let output = Command::new(&shell)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .args(["-c", SNIFF_BOOTSTRAP])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        return None;
    }
    Some(text)
}

fn is_executable(p: &str) -> bool {
    let path = PathBuf::from(p);
    std::fs::metadata(&path)
        .map(|m| {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                !m.is_dir() && m.permissions().mode() & 0o111 != 0
            }
            #[cfg(not(unix))]
            {
                !m.is_dir()
            }
        })
        .unwrap_or(false)
}

fn discover_tool_dirs() -> Vec<String> {
    let mut out = Vec::new();
    let nvm = home().join(".nvm/versions/node");
    if let Ok(rd) = std::fs::read_dir(&nvm) {
        let mut names: Vec<_> = rd.filter_map(|e| e.ok()).collect();
        names.sort_by_key(|e| e.file_name());
        for entry in names {
            out.push(
                entry
                    .path()
                    .join("bin")
                    .to_string_lossy()
                    .into_owned(),
            );
        }
    }
    for extra in [
        home().join("Library/pnpm"),
        home().join(".bun/bin"),
        home().join("go/bin"),
    ] {
        let s = extra.to_string_lossy().into_owned();
        if !s.is_empty() {
            out.push(s);
        }
    }
    out
}

fn expand_fallbacks() -> Vec<String> {
    let h = home();
    let mut list: Vec<String> = FALLBACK.iter().map(|s| (*s).to_string()).collect();
    for rel in [".rd/bin", ".nvm/versions/node/current/bin", ".cargo/bin", ".local/bin"] {
        list.push(h.join(rel).to_string_lossy().into_owned());
    }
    list
}

fn compute_path() -> PathCache {
    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
    let skip_sniff = std::env::var("KUMA_SKIP_PATH_SNIFF").ok().as_deref() == Some("1");
    // ponytail: skip interactive shell bootstrap in tests/CI; full sniff in normal daemon runs.
    let sniffed = if skip_sniff {
        std::env::var("PATH").ok()
    } else {
        sniff_path().or_else(|| std::env::var("PATH").ok())
    };
    let mut seen = std::collections::HashSet::new();
    let mut dirs = Vec::new();
    let mut directory_meta = Vec::new();

    let push = |label: &'static str, d: String, dirs: &mut Vec<String>, meta: &mut Vec<serde_json::Value>, seen: &mut std::collections::HashSet<String>| {
        let t = d.trim().to_string();
        if t.is_empty() || seen.contains(&t) {
            return;
        }
        seen.insert(t.clone());
        dirs.push(t.clone());
        meta.push(serde_json::json!({ "path": t, "source": label }));
    };

    if let Some(ref sniff) = sniffed {
        for part in sniff.split(':').filter(|p| !p.is_empty()) {
            push("sniff", part.to_string(), &mut dirs, &mut directory_meta, &mut seen);
        }
    }
    if !skip_sniff {
        for d in discover_tool_dirs() {
            push("tools", d, &mut dirs, &mut directory_meta, &mut seen);
        }
        for d in expand_fallbacks() {
            push("fallback", d, &mut dirs, &mut directory_meta, &mut seen);
        }
    }

    let path = dirs.join(":");
    PathCache {
        path,
        directories: directory_meta,
        shell,
        cached: false,
    }
}
