//! DT-SET core settings KV tests.

use kuma_store::{SettingsStore, StoreHandle, REGISTRY, RESET_KEYS};
use serde_json::{json, Map};
use std::sync::{Arc, Mutex};

static SET_ITEST: Mutex<()> = Mutex::new(());

fn open_settings() -> (
    tempfile::TempDir,
    SettingsStore,
    Arc<Mutex<Vec<kuma_store::ChangeEvent>>>,
) {
    let _guard = SET_ITEST.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let missing = dir.path().join("no-legacy.plist");
    std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", missing.to_str().unwrap());
    let store = StoreHandle::open(dir.path()).unwrap();
    std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
    let conn = store.daemon_state_connection();
    let (settings, events) = SettingsStore::with_recording_sink(conn);
    (dir, settings, events)
}

#[test]
fn dt_set_01_list_twenty_six_defaults() {
    let (_dir, settings, _ev) = open_settings();
    let list = settings.list(None, true).unwrap();
    assert_eq!(list.len(), REGISTRY.len());
    for item in &list {
        assert_eq!(item["source"], "default");
        assert!(item["stored"].is_null());
    }
}

#[test]
fn dt_set_02_set_auto_resume_and_change_event() {
    let (_dir, settings, events) = open_settings();
    let mut values = Map::new();
    values.insert("kuma.settings.autoResumeServices".into(), json!(true));
    settings.set(&values, false, None).unwrap();
    let got = settings.get("kuma.settings.autoResumeServices").unwrap();
    assert_eq!(got["effective"], true);
    assert_eq!(got["source"], "stored");
    assert!(got["updatedAt"].is_string());
    let log = events.lock().unwrap();
    assert_eq!(log.len(), 1);
    assert_eq!(log[0].reason, "set");
    assert!(log[0]
        .keys
        .contains(&"kuma.settings.autoResumeServices".to_string()));
}

#[test]
fn dt_set_03_bool_coercion_and_reject() {
    let (_dir, settings, _ev) = open_settings();
    for (raw, expect) in [("yes", true), ("1", true), ("false", false)] {
        let mut values = Map::new();
        values.insert("kuma.settings.launchAtLogin".into(), json!(raw));
        settings.set(&values, false, None).unwrap();
        let got = settings.get("kuma.settings.launchAtLogin").unwrap();
        assert_eq!(got["effective"], expect);
    }
    let mut bad = Map::new();
    bad.insert("kuma.settings.launchAtLogin".into(), json!("maybe"));
    assert!(settings.set(&bad, false, None).is_err());
}

#[test]
fn dt_set_04_enum_case_sensitive() {
    let (_dir, settings, _ev) = open_settings();
    let mut ok = Map::new();
    ok.insert(
        "kuma.settings.portConflictPolicy".into(),
        json!("kill_existing"),
    );
    settings.set(&ok, false, None).unwrap();
    for bad in ["KILL_EXISTING", "warn"] {
        let mut values = Map::new();
        values.insert("kuma.settings.portConflictPolicy".into(), json!(bad));
        assert!(settings.set(&values, false, None).is_err());
    }
}

#[test]
fn dt_set_05_batch_atomicity() {
    let (_dir, settings, events) = open_settings();
    let mut batch = Map::new();
    batch.insert("kuma.settings.appearance".into(), json!("dark"));
    batch.insert("kuma.settings.portConflictPolicy".into(), json!("nope"));
    assert!(settings.set(&batch, false, None).is_err());
    let got = settings.get("kuma.settings.appearance").unwrap();
    assert_eq!(got["source"], "default");
    assert!(events.lock().unwrap().is_empty());
}

#[test]
fn dt_set_06_null_deletes_and_legacy() {
    let (_dir, settings, _ev) = open_settings();
    let mut leg = Map::new();
    leg.insert(
        "kuma.custom_kubectl_path".into(),
        json!("/opt/legacy/bin/kubectl"),
    );
    settings.set(&leg, false, None).unwrap();
    let mut primary = Map::new();
    primary.insert(
        "kuma.settings.customKubectlPath".into(),
        json!("/usr/local/bin/kubectl"),
    );
    settings.set(&primary, false, None).unwrap();
    let mut del = Map::new();
    del.insert("kuma.settings.customKubectlPath".into(), json!(null));
    settings.set(&del, false, None).unwrap();
    let got = settings.get("kuma.settings.customKubectlPath").unwrap();
    assert_eq!(got["source"], "default");
}

#[test]
fn dt_set_07_legacy_fallback() {
    let (_dir, settings, _ev) = open_settings();
    let mut leg = Map::new();
    leg.insert(
        "kuma.custom_kubectl_path".into(),
        json!("/opt/legacy/bin/kubectl"),
    );
    settings.set(&leg, false, None).unwrap();
    let got = settings.get("kuma.settings.customKubectlPath").unwrap();
    assert_eq!(got["effective"], "/opt/legacy/bin/kubectl");
    assert_eq!(got["source"], "legacy");
}

#[test]
fn dt_set_09_reset_twenty_two_keys() {
    let (_dir, settings, events) = open_settings();
    let mut values = Map::new();
    for key in RESET_KEYS {
        let val = match key {
            "kuma.settings.appearance" => json!("dark"),
            "kuma.settings.portConflictPolicy" => json!("kill_existing"),
            "kuma.settings.notifyOnServiceFailure" | "kuma.settings.notifyOnCrash" => json!(false),
            "kuma.settings.confirmBeforeQuit" => json!(false),
            "kuma.settings.launchAtLogin" | "kuma.settings.autoResumeServices" => json!(true),
            _ => json!(""),
        };
        values.insert(key.into(), val);
    }
    values.insert("kuma.settings.quitBehavior".into(), json!("stopAll"));
    values.insert("kuma.has_completed_onboarding".into(), json!(true));
    values.insert("client.view".into(), json!(1));
    settings.set(&values, false, None).unwrap();
    let result = settings.reset().unwrap();
    assert_eq!(result.keys.len(), 22);
    assert_eq!(events.lock().unwrap().last().unwrap().reason, "reset");
    let onboarding = settings.get("kuma.has_completed_onboarding").unwrap();
    assert_eq!(onboarding["effective"], true);
    assert_eq!(
        settings.get("kuma.settings.quitBehavior").unwrap()["effective"],
        "stopAll"
    );
}

#[test]
fn dt_set_17_client_key_and_unknown() {
    let (_dir, settings, _ev) = open_settings();
    let mut values = Map::new();
    values.insert("client.view_mode".into(), json!({"a": 1}));
    settings.set(&values, false, None).unwrap();
    let got = settings.get("client.view_mode").unwrap();
    assert_eq!(got["effective"], json!({"a": 1}));
    assert!(settings.get("foo.bar").is_err());
}

#[test]
fn dt_set_18_uuid_normalization() {
    let (_dir, settings, _ev) = open_settings();
    let lower = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    let mut values = Map::new();
    values.insert(
        "kuma.settings.activeServiceIDsBeforeQuit".into(),
        json!([lower]),
    );
    settings.set(&values, false, None).unwrap();
    let got = settings
        .get("kuma.settings.activeServiceIDsBeforeQuit")
        .unwrap();
    assert_eq!(got["stored"][0], lower.to_uppercase());
    let mut bad = Map::new();
    bad.insert(
        "kuma.settings.activeServiceIDsBeforeQuit".into(),
        json!(["not-a-uuid"]),
    );
    assert!(settings.set(&bad, false, None).is_err());
}

#[test]
fn dt_set_32_onboarding_survives_reset() {
    let (_dir, settings, _ev) = open_settings();
    let mut values = Map::new();
    values.insert("kuma.has_completed_onboarding".into(), json!(true));
    settings.set(&values, false, None).unwrap();
    settings.reset().unwrap();
    let got = settings.get("kuma.has_completed_onboarding").unwrap();
    assert_eq!(got["effective"], true);
}

#[test]
fn dt_set_35_noop_skips_event() {
    let (_dir, settings, events) = open_settings();
    let mut values = Map::new();
    values.insert("kuma.settings.autoResumeServices".into(), json!(true));
    settings.set(&values, false, None).unwrap();
    settings.set(&values, false, None).unwrap();
    assert_eq!(events.lock().unwrap().len(), 1);
}

#[test]
fn dt_set_08_notify_on_crash_legacy_merge() {
    let (_dir, settings, _ev) = open_settings();
    let mut legacy = Map::new();
    legacy.insert("kuma.settings.notifyOnCrash".into(), json!(false));
    settings.set(&legacy, false, None).unwrap();
    let got = settings
        .get("kuma.settings.notifyOnServiceFailure")
        .unwrap();
    assert_eq!(got["effective"], false);
    assert_eq!(got["source"], "legacy");
    let mut on = Map::new();
    on.insert("kuma.settings.notifyOnServiceFailure".into(), json!(true));
    settings.set(&on, false, None).unwrap();
    let got = settings
        .get("kuma.settings.notifyOnServiceFailure")
        .unwrap();
    assert_eq!(got["effective"], true);
    assert_eq!(got["source"], "stored");
    assert!(
        settings.get("kuma.settings.notifyOnCrash").is_err()
            || settings
                .get("kuma.settings.notifyOnCrash")
                .map(|v| v["stored"].is_null())
                .unwrap_or(true)
    );
}

#[test]
fn dt_set_16_expected_updated_at_stale() {
    let (_dir, settings, _ev) = open_settings();
    const KEY: &str = "client.dt_set_16_token";
    let mut values = Map::new();
    values.insert(KEY.into(), json!("v1"));
    settings.set(&values, false, None).unwrap();
    let got = settings.get(KEY).unwrap();
    let ts = got["updatedAt"].as_str().unwrap().to_string();
    let mut bump = Map::new();
    bump.insert(KEY.into(), json!("v2"));
    settings.set(&bump, false, None).unwrap();
    let bumped = settings.get(KEY).unwrap();
    assert_ne!(bumped["updatedAt"].as_str().unwrap(), ts.as_str());
    let mut exp = Map::new();
    exp.insert(KEY.into(), json!(ts));
    let mut bad = Map::new();
    bad.insert(KEY.into(), json!("v3"));
    let err = settings.set(&bad, false, Some(&exp)).unwrap_err();
    assert_eq!(err.code(), "KUMA_CONFLICT_STALE");
    let mut exp_wrong = Map::new();
    exp_wrong.insert(KEY.into(), json!("2000-01-01T00:00:00.000Z"));
    assert!(settings.set(&bad, false, Some(&exp_wrong)).is_err());
    let mut exp_ok = Map::new();
    let current = settings.get(KEY).unwrap();
    exp_ok.insert(KEY.into(), json!(current["updatedAt"].as_str().unwrap()));
    values.insert(KEY.into(), json!("v4"));
    settings.set(&values, false, Some(&exp_ok)).unwrap();
}

#[test]
fn dt_set_33_client_prefix_list() {
    let (_dir, settings, _ev) = open_settings();
    let mut values = Map::new();
    values.insert("client.a".into(), json!(1));
    values.insert("client.b".into(), json!(2));
    settings.set(&values, false, None).unwrap();
    let list = settings.list(Some("client."), true).unwrap();
    assert_eq!(list.len(), 2);
    let no_client = settings.list(None, false).unwrap();
    assert_eq!(no_client.len(), REGISTRY.len());
}
