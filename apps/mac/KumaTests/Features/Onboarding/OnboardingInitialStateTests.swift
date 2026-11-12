import Foundation
import Testing
@testable import Kuma

@Suite("Onboarding Category A: Initial State & Launch Variations")
@MainActor
struct OnboardingInitialStateTests {

    // MARK: - [TC-A01] Clean Install Initial State
    @Test("TC-A01: Fresh install initializes at Step 0 with non-scanning idle state")
    func testInitialStateCleanInstall() {
        let viewModel = OnboardingViewModel()

        #expect(viewModel.currentStep == 0)
        #expect(viewModel.totalSteps == 4)
        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasInitialScanned == false)
        #expect(viewModel.canGoNext == true)
        #expect(viewModel.canGoPrev == false)
        #expect(viewModel.pathValidationError == nil)
        #expect(viewModel.engineDependencies.isEmpty)
        #expect(viewModel.tunnelingDependencies.isEmpty)
    }

    // MARK: - [TC-A02] Launch Returning User State
    @Test("TC-A02: Returning user with hasCompletedOnboarding skips onboarding to mainWorkspace")
    func testLaunchReturningUser() {
        let suiteName = "kuma.tests.onboarding.initial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = KumaSettingsKey.hasCompletedOnboarding
        // Simulate existing completed user
        defaults.set(true, forKey: key)
        let coordinator = AppCoordinator(userDefaults: defaults)
        #expect(coordinator.currentPhase == .mainWorkspace)
    }

    // MARK: - [TC-A03] Corrupted Defaults Fallback
    @Test("TC-A03: Missing or non-boolean value in settings defaults safely falls back to onboarding phase")
    func testCorruptedDefaultsFallback() {
        let suiteName = "kuma.tests.onboarding.corrupted.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = KumaSettingsKey.hasCompletedOnboarding
        // Set garbage non-boolean string value
        defaults.set("corrupted_value_xyz", forKey: key)
        let coordinator = AppCoordinator(userDefaults: defaults)
        #expect(coordinator.currentPhase == .onboarding)
    }

    // MARK: - [TC-A04] Navigation while Scan in Progress
    @Test("TC-A04: User advancing to Step 1 while scan is in-flight remains non-blocking and safe")
    func testSlowPreScanNavigation() async {
        let viewModel = OnboardingViewModel()
        #expect(viewModel.currentStep == 0)

        // Launch background scan without awaiting completion immediately
        let scanTask = Task {
            await viewModel.runScan(isManualRescan: true)
        }

        // User immediately clicks Continue to Step 1
        #expect(viewModel.canGoNext == true)
        viewModel.nextStep()
        #expect(viewModel.currentStep == 1)

        // Await scan to resolve
        await scanTask.value

        // State must resolve cleanly in Step 1
        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasInitialScanned == true)
        #expect(viewModel.engineDependencies.count == 4)
        #expect(viewModel.tunnelingDependencies.count == 2)
    }
}
