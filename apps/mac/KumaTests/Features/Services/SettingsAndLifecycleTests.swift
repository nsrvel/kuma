import Foundation
import Testing
@testable import Kuma

@Suite("Feature 06 - Category E: Settings & Lifecycle Integration", .serialized)
@MainActor
struct SettingsAndLifecycleTests {

    // MARK: - [TC-E01] Confirm Before Quit Configuration Resolution
    @Test("TC-E01: confirmBeforeQuit defaults to true and respects user preference")
    func testConfirmBeforeQuitDefaultAndOverride() {
        let defaults = UserDefaults(suiteName: "SettingsAndLifecycleTests")!
        defaults.removePersistentDomain(forName: "SettingsAndLifecycleTests")

        // Default should be true
        let defaultVal = KumaSettingsKey.bool(forKey: KumaSettingsKey.confirmBeforeQuit, defaultValue: true, defaults: defaults)
        #expect(defaultVal == true)

        // Set to false
        defaults.set(false, forKey: KumaSettingsKey.confirmBeforeQuit)
        let modifiedVal = KumaSettingsKey.bool(forKey: KumaSettingsKey.confirmBeforeQuit, defaultValue: true, defaults: defaults)
        #expect(modifiedVal == false)
    }

    // MARK: - [TC-E02] Active Running Service IDs Query
    @Test("TC-E02: ProcessRegistry tracks and returns activeRunningServiceIDs")
    func testActiveRunningServiceIDsTracking() async throws {
        let registry = ProcessRegistry.shared
        let testServiceID = UUID()

        let runningBefore = await registry.activeRunningServiceIDs()
        #expect(!runningBefore.contains(testServiceID))

        let pid = try await registry.launch(
            serviceID: testServiceID,
            serviceName: "Test Auto Service",
            executable: "/bin/sleep",
            arguments: ["5"]
        )
        #expect(pid > 0)

        let runningDuring = await registry.activeRunningServiceIDs()
        #expect(runningDuring.contains(testServiceID))

        await registry.stop(serviceID: testServiceID)

        let runningAfter = await registry.activeRunningServiceIDs()
        #expect(!runningAfter.contains(testServiceID))
    }

    // MARK: - [TC-E03] Auto-Start Service Persistence Format
    @Test("TC-E03: activeServiceIDsBeforeQuit saves and reads array of UUID strings")
    func testActiveServiceIDsPersistence() {
        let defaults = UserDefaults.standard
        let id1 = UUID()
        let id2 = UUID()
        let idsToSave = [id1.uuidString, id2.uuidString]

        defaults.set(idsToSave, forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)

        let loadedStrings = defaults.stringArray(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)
        #expect(loadedStrings != nil)
        #expect(loadedStrings?.count == 2)
        #expect(loadedStrings?.contains(id1.uuidString) == true)
        #expect(loadedStrings?.contains(id2.uuidString) == true)

        // Clean up
        defaults.removeObject(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)
    }

    // MARK: - [TC-E04] Notify on Service Crash Settings Resolution
    @Test("TC-E04: notifyOnServiceFailure defaults to true")
    func testNotifyOnCrashDefaults() {
        let defaults = UserDefaults(suiteName: "SettingsAndLifecycleTestsNotify")!
        defaults.removePersistentDomain(forName: "SettingsAndLifecycleTestsNotify")

        let notifyFailure = KumaSettingsKey.bool(
            forKey: KumaSettingsKey.notifyOnServiceFailure,
            defaultValue: true,
            fallbackKey: KumaSettingsKey.legacyNotifyOnCrash,
            defaults: defaults
        )

        #expect(notifyFailure == true)
    }

    // MARK: - [TC-E05] Auto-Resume Services On Launch Success
    @Test("TC-E05: ServicesDeckViewModel resumes candidate services and clears them from saved list")
    func testAutoResumeServicesOnLaunchSuccess() async throws {
        let harness = ServicesTestHarness()
        let suiteName = "TestAutoResume_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Seed 2 services
        let (s1, _) = try await harness.seedServiceWithProvider(name: "Resume Service 1", providerType: .shell)
        let (s2, _) = try await harness.seedServiceWithProvider(name: "Resume Service 2", providerType: .shell)

        // Save s1 and s2 in activeServiceIDsBeforeQuit
        defaults.set([s1.id.uuidString, s2.id.uuidString], forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)
        defaults.set(true, forKey: KumaSettingsKey.autoResumeServices)

        let deckVM = ServicesDeckViewModel(
            serviceRepository: harness.serviceRepository,
            userDefaults: defaults
        )

        await deckVM.loadWorkspaceAsync(workspaceID: harness.defaultWorkspaceID)

        // The candidate IDs should be removed from saved list so they aren't restarted repeatedly
        let remaining = defaults.stringArray(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit) ?? []
        #expect(!remaining.contains(s1.id.uuidString))
        #expect(!remaining.contains(s2.id.uuidString))

        // Initial load should be marked true
        #expect(deckVM.hasInitialLoaded == true)
        #expect(deckVM.snapshots.count == 2)
    }

    // MARK: - [TC-E06] Auto-Resume Respects Disabled Flag And Settings Toggle
    @Test("TC-E06: autoResumeServices skips disabled services and honors setting toggle")
    func testAutoResumeRespectsDisabledAndSettings() async throws {
        let harness = ServicesTestHarness()
        let suiteName = "TestAutoResumeDisabled_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let (s1, _) = try await harness.seedServiceWithProvider(name: "Disabled Service", providerType: .shell)
        // Mark s1 as disabled
        var disabledService = s1
        disabledService.isDisabled = true
        try await harness.serviceRepository.updateService(disabledService)

        // Save s1 ID
        defaults.set([s1.id.uuidString], forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)
        defaults.set(true, forKey: KumaSettingsKey.autoResumeServices)

        let deckVM = ServicesDeckViewModel(
            serviceRepository: harness.serviceRepository,
            userDefaults: defaults
        )

        await deckVM.loadWorkspaceAsync(workspaceID: harness.defaultWorkspaceID)

        // Since it was disabled, candidates list is empty, so it should not be removed from saved list or started
        let remaining = defaults.stringArray(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit) ?? []
        #expect(remaining.contains(s1.id.uuidString))
        #expect(deckVM.runtime(for: s1.id).status.isOperational != true)

        // Test with autoResumeServices = false
        defaults.set(false, forKey: KumaSettingsKey.autoResumeServices)
        let (s2, _) = try await harness.seedServiceWithProvider(name: "Active Service", providerType: .shell)
        defaults.set([s2.id.uuidString], forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)

        let deckVM2 = ServicesDeckViewModel(
            serviceRepository: harness.serviceRepository,
            userDefaults: defaults
        )
        await deckVM2.loadWorkspaceAsync(workspaceID: harness.defaultWorkspaceID)

        let remaining2 = defaults.stringArray(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit) ?? []
        #expect(remaining2.contains(s2.id.uuidString))
    }

    // MARK: - [TC-E07] Auto-Resume Preserves Other Workspace IDs
    @Test("TC-E07: autoResume preserves IDs from other workspaces not present in current workspace")
    func testAutoResumePreservesOtherWorkspaceIDs() async throws {
        let harness = ServicesTestHarness()
        let suiteName = "TestAutoResumeOtherWS_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let (s1, _) = try await harness.seedServiceWithProvider(name: "Current WS Service", providerType: .shell)
        let otherWorkspaceServiceID = UUID()

        // Store both s1 and an ID from another workspace
        defaults.set([s1.id.uuidString, otherWorkspaceServiceID.uuidString], forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)
        defaults.set(true, forKey: KumaSettingsKey.autoResumeServices)

        let deckVM = ServicesDeckViewModel(
            serviceRepository: harness.serviceRepository,
            userDefaults: defaults
        )

        await deckVM.loadWorkspaceAsync(workspaceID: harness.defaultWorkspaceID)

        let remaining = defaults.stringArray(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit) ?? []
        // s1 should be consumed
        #expect(!remaining.contains(s1.id.uuidString))
        // other workspace service ID must remain intact for when that workspace is opened
        #expect(remaining.contains(otherWorkspaceServiceID.uuidString))
    }
}
