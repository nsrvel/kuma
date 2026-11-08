use anyhow::{bail, Context, Result};
use kuma_protocol::paths;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

const LABEL: &str = "com.kuma.daemon";

pub fn install() -> Result<()> {
    let exe = std::env::current_exe().context("resolve kuma binary path")?;
    let home = dirs_home()?;
    let plist_path = home
        .join("Library/LaunchAgents")
        .join(format!("{LABEL}.plist"));
    fs::create_dir_all(plist_path.parent().unwrap()).context("create LaunchAgents dir")?;
    let data_dir = paths::data_dir();
    let plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>{LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{}</string>
    <string>daemon</string>
    <string>run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>KUMA_DATA_DIR</key><string>{}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>{}/daemon.log</string>
  <key>StandardErrorPath</key><string>{}/daemon.err.log</string>
</dict></plist>"#,
        exe.display(),
        data_dir.display(),
        data_dir.display(),
        data_dir.display(),
    );
    fs::write(&plist_path, plist).context("write LaunchAgent plist")?;
    let status = Command::new("launchctl")
        .args(["load", "-w"])
        .arg(&plist_path)
        .status()
        .context("launchctl load")?;
    if !status.success() {
        bail!("launchctl load failed with {status}");
    }
    Ok(())
}

pub fn uninstall() -> Result<()> {
    let home = dirs_home()?;
    let plist_path = home
        .join("Library/LaunchAgents")
        .join(format!("{LABEL}.plist"));
    let _ = Command::new("launchctl")
        .args(["unload", "-w"])
        .arg(&plist_path)
        .status();
    if plist_path.exists() {
        fs::remove_file(&plist_path).context("remove plist")?;
    }
    Ok(())
}

fn dirs_home() -> Result<PathBuf> {
  std::env::var("HOME")
        .map(PathBuf::from)
        .context("HOME not set")
}
