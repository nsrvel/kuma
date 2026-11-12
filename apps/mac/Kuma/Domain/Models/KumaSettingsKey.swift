import Foundation

/// Centralized configuration keys for user preferences, persistent settings, and binary paths.
/// Eliminates hardcoded magic strings and prevents typo-induced state desync across features.
public nonisolated enum KumaSettingsKey {
    // MARK: - App & Lifecycle
    public static let hasCompletedOnboarding = "kuma.has_completed_onboarding"

    // MARK: - General & App Settings
    public static let launchAtLogin = "kuma.settings.launchAtLogin"
    public static let autoResumeServices = "kuma.settings.autoResumeServices"
    public static let activeServiceIDsBeforeQuit = "kuma.settings.activeServiceIDsBeforeQuit"
    public static let confirmBeforeQuit = "kuma.settings.confirmBeforeQuit"
    public static let quitBehavior = "kuma.settings.quitBehavior"
    public static let appearance = "kuma.settings.appearance"

    // MARK: - Engine & CLI Binary Paths
    public static let defaultShell = "kuma.settings.defaultShell"
    public static let customKubectlPath = "kuma.settings.customKubectlPath"
    public static let customKubeconfigPath = "kuma.settings.customKubeconfigPath"
    public static let customDockerPath = "kuma.settings.customDockerPath"
    public static let customPodmanPath = "kuma.settings.customPodmanPath"

    // MARK: - Tunneling Custom Binary Paths & Config
    public static let cloudflaredPath = "kuma.settings.cloudflaredPath"
    public static let customNgrokPath = "kuma.settings.customNgrokPath"

    // MARK: - Notifications & Safety
    public static let notifyOnServiceFailure = "kuma.settings.notifyOnServiceFailure"
    public static let portConflictPolicy = "kuma.settings.portConflictPolicy"

    // MARK: - Logs & Buffer
    public static let logRetentionLimit = "kuma.settings.logRetentionLimit"
    public static let clearLogsOnSwitch = "kuma.settings.clearLogsOnSwitch"

    // MARK: - Legacy Compatibility Keys (Fallback reading)
    public static let legacyKubectlPath = "kuma.custom_kubectl_path"
    public static let legacyKubeconfigPath = "kuma.custom_kubeconfig_path"
    public static let legacyDockerPath = "kuma.custom_docker_path"
    public static let legacyPodmanPath = "kuma.custom_podman_path"
    public static let legacyCloudflaredPath = "kuma.custom_cloudflared_path"
    public static let legacyNgrokPath = "kuma.custom_ngrok_path"
    public static let legacyNotifyOnCrash = "kuma.settings.notifyOnCrash"

    /// Helper to resolve a string preference checking new key first, then legacy key fallback.
    public nonisolated static func string(forKey primaryKey: String, fallbackKey: String? = nil, defaults: UserDefaults = .standard) -> String? {
        if let val = defaults.string(forKey: primaryKey), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return val
        }
        if let fallbackKey, let fallbackVal = defaults.string(forKey: fallbackKey), !fallbackVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallbackVal
        }
        return nil
    }

    /// Helper to resolve a boolean preference with an explicit default value.
    public nonisolated static func bool(
        forKey key: String,
        defaultValue: Bool,
        fallbackKey: String? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if defaults.object(forKey: key) != nil, let object = defaults.object(forKey: key) as? Bool {
            return object
        }
        if let fallbackKey, defaults.object(forKey: fallbackKey) != nil, let object = defaults.object(forKey: fallbackKey) as? Bool {
            return object
        }
        return defaultValue
    }

    /// Helper to resolve an integer preference with an explicit default value.
    public nonisolated static func integer(forKey key: String, defaultValue: Int, defaults: UserDefaults = .standard) -> Int {
        if let object = defaults.object(forKey: key) as? Int {
            return object
        }
        return defaultValue
    }
}
