import Foundation
import Testing
@testable import Kuma

@Suite("Settings Category A: Initial State & Baseline Contracts", .serialized)
@MainActor
struct SettingsInitialStateTests {

    // MARK: - [TC-A01] Clean Install Default General Settings
    @Test("TC-A01: Fresh install initializes general preferences with safe baseline contracts")
    func testDefaultGeneralSettings() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)

        #expect(viewModel.launchAtLogin == false)
        #expect(viewModel.autoResumeServices == false)
        #expect(viewModel.confirmBeforeQuit == true)
    }

    // MARK: - [TC-A02] Clean Install Default Appearance
    @Test("TC-A02: Fresh install initializes appearance with system default theme")
    func testDefaultAppearance() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)

        #expect(viewModel.appearance == .system)
        #expect(viewModel.appearance.title == "System Default")
        #expect(KumaAppearance.allCases.count == 3)
    }

    // MARK: - [TC-A03] Clean Install Default Engine & CLI Paths
    @Test("TC-A03: Fresh install leaves custom CLI override paths empty")
    func testDefaultEnginePaths() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)

        #expect(viewModel.customKubectlPath.isEmpty)
        #expect(viewModel.customKubeconfigPath.isEmpty)
        #expect(viewModel.customDockerPath.isEmpty)
        #expect(viewModel.customPodmanPath.isEmpty)
        #expect(viewModel.cloudflaredPath.isEmpty)
        #expect(viewModel.customNgrokPath.isEmpty)
    }

    // MARK: - [TC-A04] Clean Install Default Shell
    @Test("TC-A04: Fresh install defaults to /bin/zsh shell")
    func testDefaultShellOption() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)

        #expect(viewModel.defaultShell == "/bin/zsh")
        #expect(KumaShellLaunchConfiguration.validatedShellPath(defaults: harness.userDefaults) == "/bin/zsh")
        #expect(DefaultShell.zsh.label == "Zsh")
        #expect(DefaultShell.bash.label == "Bash")
        #expect(DefaultShell.fish.label == "Fish")
    }

    // MARK: - [TC-A05] Clean Install Default Notification & Safety
    @Test("TC-A05: Fresh install initializes crash notifications to enabled")
    func testDefaultNotificationSettings() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)

        #expect(viewModel.notifyOnServiceFailure == true)
    }

    // MARK: - [TC-A07] Clean Install Default Port Conflict Policy
    @Test("TC-A07: Fresh install defaults to warnAndBlock port conflict policy")
    func testDefaultPortConflictPolicy() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)

        #expect(viewModel.portConflictPolicy == .warnAndBlock)
        #expect(viewModel.portConflictPolicy.title == "Warn & Prevent Start")
        #expect(PortConflictPolicy.allCases.count == 2)
    }
}
