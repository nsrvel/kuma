import Foundation

/// Resolves CLI/tunnel binaries using Settings overrides, then system PATH.
public enum KumaSettingsExecutableResolver {
    public static func resolve(_ command: String, settingsKey: String) async -> String? {
        let custom = KumaSettingsKey.string(forKey: settingsKey)
        return await DependencyChecker.resolvedPath(for: command, customPath: custom)
    }

    public static func kubectl() async -> String? {
        await resolve("kubectl", settingsKey: KumaSettingsKey.customKubectlPath)
    }

    public static func docker() async -> String? {
        await resolve("docker", settingsKey: KumaSettingsKey.customDockerPath)
    }

    public static func podman() async -> String? {
        await resolve("podman", settingsKey: KumaSettingsKey.customPodmanPath)
    }

    public static func cloudflared() async -> String? {
        await resolve("cloudflared", settingsKey: KumaSettingsKey.cloudflaredPath)
    }

    public static func ngrok() async -> String? {
        await resolve("ngrok", settingsKey: KumaSettingsKey.customNgrokPath)
    }
}
