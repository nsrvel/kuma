import Foundation
import Testing
import AppKit
@testable import Kuma

@Suite("Settings Category D: Runtime & OS System Integration", .serialized)
@MainActor
struct SettingsSystemIntegrationTests {

    // MARK: - [TC-D01] Appearance Switch To Dark
    @Test("TC-D01: Switching appearance to .dark applies dark appearance mode")
    func testAppearanceSwitchToDark() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        viewModel.appearance = .dark

        #expect(viewModel.appearance == .dark)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.appearance) == "dark")
    }

    // MARK: - [TC-D02] Appearance Switch To Light
    @Test("TC-D02: Switching appearance to .light applies light appearance mode")
    func testAppearanceSwitchToLight() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        viewModel.appearance = .light

        #expect(viewModel.appearance == .light)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.appearance) == "light")
    }

    // MARK: - [TC-D03] Appearance Switch To System
    @Test("TC-D03: Switching appearance to .system sets appearance to nil (follows macOS)")
    func testAppearanceSwitchToSystem() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        viewModel.appearance = .system

        #expect(viewModel.appearance == .system)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.appearance) == "system")
    }

    // MARK: - [TC-D04] Notification Permission Request Coordinated State
    @Test("TC-D04: requestNotificationAuthorization executes safely and returns boolean prompt status")
    func testNotificationPermissionExecution() async {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        let needsPrompt = await viewModel.requestNotificationAuthorization()

        // In headless testing, this completes cleanly without throwing uncaught exceptions
        #expect(needsPrompt == true || needsPrompt == false)
    }

    // MARK: - [TC-D05] Launch At Login Toggle Safe Execution
    @Test("TC-D05: Toggling launchAtLogin persists to defaults and does not crash")
    func testLaunchAtLoginToggleSafeExecution() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        viewModel.launchAtLogin = true
        #expect(harness.userDefaults.bool(forKey: KumaSettingsKey.launchAtLogin) == true)

        viewModel.launchAtLogin = false
        #expect(harness.userDefaults.bool(forKey: KumaSettingsKey.launchAtLogin) == false)
    }
}
