import Foundation
import Testing
@testable import Kuma

@Suite("Feature 00 - Category B: App Coordinator, Phase Transitions & Storage Integrity", .serialized)
@MainActor
struct AppCoordinatorTests {

    private let key = KumaSettingsKey.hasCompletedOnboarding

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "kuma.tests.coordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    // MARK: - [TC-B01] Initial Phase Clean Install
    @Test("TC-B01: First launch with no defaults key defaults to .onboarding")
    func testInitialPhaseFirstLaunchClean() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = AppCoordinator(userDefaults: defaults)
        #expect(coordinator.currentPhase == .onboarding)
    }

    // MARK: - [TC-B02] Initial Phase Returning User
    @Test("TC-B02: Launch with hasCompletedOnboarding == true starts in .mainWorkspace")
    func testInitialPhaseReturningUser() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: key)
        let coordinator = AppCoordinator(userDefaults: defaults)
        #expect(coordinator.currentPhase == .mainWorkspace)
    }

    // MARK: - [TC-B03] Explicit Initial Phase Override
    @Test("TC-B03: Explicit initialPhase parameter overrides UserDefaults state")
    func testExplicitInitialPhaseOverride() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: key)
        let coordinator = AppCoordinator(initialPhase: .onboarding, userDefaults: defaults)
        #expect(coordinator.currentPhase == .onboarding)
    }

    // MARK: - [TC-B04] Transition to MainWorkspace Persists True
    @Test("TC-B04: transitionTo(.mainWorkspace) updates state and persists true")
    func testTransitionToMainWorkspacePersistsTrue() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: key)
        let coordinator = AppCoordinator(initialPhase: .onboarding, userDefaults: defaults)
        #expect(coordinator.currentPhase == .onboarding)

        coordinator.transitionTo(.mainWorkspace)
        #expect(coordinator.currentPhase == .mainWorkspace)
        #expect(defaults.bool(forKey: key) == true)
    }

    // MARK: - [TC-B05] Transition to Onboarding Persists False
    @Test("TC-B05: transitionTo(.onboarding) updates state and persists false")
    func testTransitionToOnboardingPersistsFalse() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: key)
        let coordinator = AppCoordinator(initialPhase: .mainWorkspace, userDefaults: defaults)
        #expect(coordinator.currentPhase == .mainWorkspace)

        coordinator.transitionTo(.onboarding)
        #expect(coordinator.currentPhase == .onboarding)
        #expect(defaults.bool(forKey: key) == false)
    }

    // MARK: - [TC-B06] Reset to Onboarding Convenience
    @Test("TC-B06: resetToOnboarding() sets currentPhase to .onboarding and persists false")
    func testResetToOnboardingConvenience() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: key)
        let coordinator = AppCoordinator(initialPhase: .mainWorkspace, userDefaults: defaults)

        coordinator.resetToOnboarding()
        #expect(coordinator.currentPhase == .onboarding)
        #expect(defaults.bool(forKey: key) == false)
    }

    // MARK: - [TC-B07] Corrupted Defaults Key Fallback
    @Test("TC-B07: Corrupted non-boolean storage falls back safely to .onboarding")
    func testCorruptedDefaultsKeyFallback() {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("corrupted_string_value", forKey: key)
        let coordinator = AppCoordinator(userDefaults: defaults)
        #expect(coordinator.currentPhase == .onboarding)
    }
}
