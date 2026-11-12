import Foundation
import AppKit
import os

extension DataPortService {
    // MARK: - Factory Reset & Relaunch

    @MainActor
    public static func resetAllAppStorage(defaults: UserDefaults = .standard) async {
        // 0. Terminate all running service processes / tunnels cleanly
        await ProcessRegistry.shared.terminateAll()

        // 1. Wipe UserDefaults
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
        if !isTesting, let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        } else if isTesting {
            // In testing, remove known settings keys safely without blowing away the host test runner's standard defaults
            defaults.removeObject(forKey: KumaSettingsKey.hasCompletedOnboarding)
            defaults.removeObject(forKey: KumaSettingsKey.customKubectlPath)
            defaults.removeObject(forKey: KumaSettingsKey.customKubeconfigPath)
            defaults.removeObject(forKey: KumaSettingsKey.customDockerPath)
            defaults.removeObject(forKey: KumaSettingsKey.customPodmanPath)
            defaults.removeObject(forKey: KumaSettingsKey.cloudflaredPath)
            defaults.removeObject(forKey: KumaSettingsKey.customNgrokPath)
        }

        // 2. Wipe SQLite DB
        try? AppDatabase.shared.wipeAndResetDatabase()

        // 3. Clear Local Workspace Images
        WorkspaceImageStore.shared.clearCache()
        let imagesDir = WorkspaceImageStore.shared.imagesDirectoryURL()
        try? FileManager.default.removeItem(at: imagesDir)

        logger.info("Cleared all user defaults, SQLite database records, and workspace images")
    }

    @MainActor
    public static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"\(bundlePath)\""
        ]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            // Fallback to NSWorkspace if process spawning fails
            let url = URL(fileURLWithPath: bundlePath)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                Task { @MainActor in
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
