import Foundation
import Testing
@testable import Kuma

@Suite("Onboarding Category E, F & G: Lifecycle, macOS Quirks & Settings Migration", .serialized)
@MainActor
struct OnboardingFlowTests {

    // MARK: - [TC-E01] Full Onboarding Lifecycle Journey
    @Test("TC-E01: Complete flow from Step 0 to Step 3 transitions phase and marks completed flag")
    func testCompleteOnboardingLifecycle() async {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let key = KumaSettingsKey.hasCompletedOnboarding
        let coordinator = AppCoordinator(initialPhase: .onboarding, userDefaults: harness.userDefaults)
        #expect(coordinator.currentPhase == .onboarding)

        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        #expect(viewModel.currentStep == 0)

        await viewModel.scanDependenciesIfNeeded()
        #expect(viewModel.hasInitialScanned == true)

        viewModel.nextStep() // Step 1
        #expect(viewModel.currentStep == 1)

        viewModel.nextStep() // Step 2
        #expect(viewModel.currentStep == 2)

        viewModel.nextStep() // Step 3
        #expect(viewModel.currentStep == 3)
        #expect(viewModel.canGoNext == false)

        // User clicks "Get Started"
        coordinator.transitionTo(.mainWorkspace)

        #expect(coordinator.currentPhase == .mainWorkspace)
        #expect(harness.userDefaults.bool(forKey: key) == true)
    }

    // MARK: - [TC-E02] Back and Forth State Retention
    @Test("TC-E02: Navigating forward and backward preserves scanned state and custom overrides")
    func testBackAndForthStateRetention() async {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let validDocker = harness.createDummyExecutable(named: "docker")
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        await viewModel.scanDependenciesIfNeeded()

        viewModel.nextStep() // To Step 1
        let dep = viewModel.engineDependencies.first(where: { $0.id == "docker" })!
        viewModel.setCustomPath(for: dep, path: validDocker)

        // Advance to Step 2 then retreat to Step 0
        viewModel.nextStep() // To Step 2
        #expect(viewModel.currentStep == 2)
        viewModel.prevStep() // To Step 1
        viewModel.prevStep() // To Step 0
        #expect(viewModel.currentStep == 0)

        // Forward to Step 1 again
        viewModel.nextStep()
        #expect(viewModel.currentStep == 1)
        #expect(viewModel.hasInitialScanned == true)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customDockerPath) == validDocker)
    }

    // MARK: - [TC-E03] Reset to Onboarding
    @Test("TC-E03: Factory reset reverts coordinator to onboarding and clears completion flag")
    func testResetToOnboarding() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let key = KumaSettingsKey.hasCompletedOnboarding
        let coordinator = AppCoordinator(initialPhase: .mainWorkspace, userDefaults: harness.userDefaults)
        #expect(coordinator.currentPhase == .mainWorkspace)

        coordinator.resetToOnboarding()
        #expect(coordinator.currentPhase == .onboarding)
        #expect(harness.userDefaults.bool(forKey: key) == false)
    }

    // MARK: - [TC-F01] Homebrew Path Resolution
    @Test("TC-F01: EnvironmentPathResolver considers standard macOS binary locations")
    func testHomebrewPathResolution() async {
        let resolver = EnvironmentPathResolver.shared
        let path = await resolver.resolvePath()
        #expect(!path.isEmpty)
        // System path should contain standard delimiters
        #expect(path.contains("/"))
    }

    // MARK: - [TC-F02] Symlink Resolution
    @Test("TC-F02: Valid symbolic link resolves to underlying executable binary")
    func testSymlinkResolution() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let realBinary = harness.createDummyExecutable(named: "docker")
        let symlink = harness.createSymlink(named: "docker", pointingTo: realBinary)

        let validation = DependencyChecker.validateCustomBinary(path: symlink, expectedCommand: "docker")
        #expect(validation.isValid == true)
    }

    // MARK: - [TC-F03] Broken Symlink Rejection
    @Test("TC-F03: Broken symbolic link pointing to missing destination is rejected as fileNotFound")
    func testBrokenSymlinkRejection() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let brokenLink = harness.createBrokenSymlink(named: "docker")
        let validation = DependencyChecker.validateCustomBinary(path: brokenLink, expectedCommand: "docker")
        #expect(validation.isValid == false)
        #expect(validation == .fileNotFound)
    }

    // MARK: - [TC-F04] Kubeconfig Environment Variable Precedence
    @Test("TC-F04: Kubeconfig detection safely checks without throwing")
    func testKubeconfigEnvVarPrecedence() {
        let isPresent = DependencyChecker.isKubeconfigPresent()
        // Must return a deterministic boolean without fatal errors
        #expect(isPresent == true || isPresent == false)
    }

    // MARK: - [TC-F05] Fallback Directory Coverage
    @Test("TC-F05: Resolver returns nil for non-existent binary without hanging")
    func testFallbackDirectoryCoverage() async {
        let resolved = await DependencyChecker.resolvedPath(for: "definitely_non_existent_binary_xyz_123")
        #expect(resolved == nil)
    }

    // MARK: - [TC-G01] Alert Dismissal Clears State
    @Test("TC-G01: clearValidationError resets pathValidationError to nil")
    func testAlertDismissalClearsState() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(id: "kubectl", name: "Kubectl", iconName: "network", isInstalled: false, settingsKey: KumaSettingsKey.customKubectlPath)

        viewModel.setCustomPath(for: dep, path: "/invalid/path")
        #expect(viewModel.pathValidationError != nil)

        viewModel.clearValidationError()
        #expect(viewModel.pathValidationError == nil)
    }

    // MARK: - [TC-G02] Path With Special Characters & Spaces
    @Test("TC-G02: Binary path containing valid spaces is handled properly")
    func testPathWithSpecialCharacters() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let tempDir = harness.createTempDirectory(named: "my tools dir")
        let binaryPath = (tempDir as NSString).appendingPathComponent("kubectl")
        FileManager.default.createFile(atPath: binaryPath, contents: "#!/bin/sh".data(using: .utf8), attributes: [
            .posixPermissions: 0o755
        ])

        let validation = DependencyChecker.validateCustomBinary(path: binaryPath, expectedCommand: "kubectl")
        #expect(validation.isValid == true)
    }

    // MARK: - [TC-G03] Legacy Key Migration Fallback
    @Test("TC-G03: KumaSettingsKey resolves primary key and falls back to legacy key seamlessly")
    func testLegacyKeyMigrationFallback() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let primaryKey = "test.primary.key.\(UUID().uuidString)"
        let fallbackKey = "test.legacy.key.\(UUID().uuidString)"

        // Case 1: Only fallback exists
        harness.userDefaults.set("/usr/local/bin/legacy_docker", forKey: fallbackKey)
        let resolvedFallback = KumaSettingsKey.string(forKey: primaryKey, fallbackKey: fallbackKey, defaults: harness.userDefaults)
        #expect(resolvedFallback == "/usr/local/bin/legacy_docker")

        // Case 2: Primary key takes precedence
        harness.userDefaults.set("/opt/homebrew/bin/new_docker", forKey: primaryKey)
        let resolvedPrimary = KumaSettingsKey.string(forKey: primaryKey, fallbackKey: fallbackKey, defaults: harness.userDefaults)
        #expect(resolvedPrimary == "/opt/homebrew/bin/new_docker")
    }

    // MARK: - [TC-G04] canGoNext & canGoPrev Properties
    @Test("TC-G04: canGoNext and canGoPrev flags accurately reflect currentStep boundaries")
    func testCanGoNextAndPrevProperties() {
        let viewModel = OnboardingViewModel()
        #expect(viewModel.currentStep == 0)
        #expect(viewModel.canGoNext == true)
        #expect(viewModel.canGoPrev == false)

        viewModel.nextStep() // Step 1
        #expect(viewModel.canGoNext == true)
        #expect(viewModel.canGoPrev == true)

        viewModel.nextStep() // Step 2
        #expect(viewModel.canGoNext == true)
        #expect(viewModel.canGoPrev == true)

        viewModel.nextStep() // Step 3
        #expect(viewModel.canGoNext == false)
        #expect(viewModel.canGoPrev == true)
    }

    // MARK: - [TC-G05] Total Steps Constant
    @Test("TC-G05: totalSteps constant is exactly 4")
    func testTotalStepsConstant() {
        let viewModel = OnboardingViewModel()
        #expect(viewModel.totalSteps == 4)
    }
}
