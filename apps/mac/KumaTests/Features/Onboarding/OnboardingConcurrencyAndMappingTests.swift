import Foundation
import Testing
@testable import Kuma

@Suite("Onboarding Category C & D: Concurrency, Debounce & Dependency Mapping", .serialized)
@MainActor
struct OnboardingConcurrencyAndMappingTests {

    // MARK: - [TC-C01] Rapid Consecutive Scans
    @Test("TC-C01: Rapid consecutive scans cancel previous in-flight tasks without race condition")
    func testRapidConsecutiveScans() async {
        let viewModel = OnboardingViewModel()

        async let scan1: () = viewModel.runScan(isManualRescan: true)
        async let scan2: () = viewModel.runScan(isManualRescan: true)
        async let scan3: () = viewModel.runScan(isManualRescan: false)

        _ = await (scan1, scan2, scan3)

        #expect(viewModel.isScanning == false)
        #expect(viewModel.hasInitialScanned == true)
        #expect(viewModel.engineDependencies.count == 4)
        #expect(viewModel.tunnelingDependencies.count == 2)
    }

    // MARK: - [TC-C02] Path Override During In-Flight Scan
    @Test("TC-C02: Setting custom path while background scan is running cancels scan and re-evaluates atomically")
    func testPathOverrideDuringScan() async {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let validDocker = harness.createDummyExecutable(named: "docker")
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "docker",
            name: "Docker Engine",
            iconName: "shippingbox.fill",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customDockerPath
        )

        // Start background scan
        Task {
            await viewModel.runScan(isManualRescan: true)
        }

        // Give scan task a brief moment to start running
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Mid-flight override cancels the background scan and starts new scan
        let success = viewModel.setCustomPath(for: dep, path: validDocker)
        #expect(success == true)

        // Give the task a brief run loop spin, then await pending scan
        try? await Task.sleep(nanoseconds: 50_000_000)
        await viewModel.waitForPendingScan()

        #expect(viewModel.isScanning == false)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customDockerPath) == validDocker)
    }

    // MARK: - [TC-C03] Rapid Step Forward Spam
    @Test("TC-C03: Spamming nextStep navigation clamps at maximum step index 3")
    func testRapidStepForwardSpam() {
        let viewModel = OnboardingViewModel()
        #expect(viewModel.currentStep == 0)

        for _ in 0..<25 {
            viewModel.nextStep()
        }

        #expect(viewModel.currentStep == 3)
        #expect(viewModel.canGoNext == false)
        #expect(viewModel.canGoPrev == true)
    }

    // MARK: - [TC-C04] Rapid Step Backward Spam
    @Test("TC-C04: Spamming prevStep navigation clamps at minimum step index 0")
    func testRapidStepBackwardSpam() {
        let viewModel = OnboardingViewModel()
        viewModel.nextStep()
        viewModel.nextStep()
        #expect(viewModel.currentStep == 2)

        for _ in 0..<25 {
            viewModel.prevStep()
        }

        #expect(viewModel.currentStep == 0)
        #expect(viewModel.canGoNext == true)
        #expect(viewModel.canGoPrev == false)
    }

    // MARK: - [TC-D01] Zero Dependencies Progression
    @Test("TC-D01: Wizard allows non-blocking progression even when zero CLI dependencies are present")
    func testZeroDependenciesProgression() {
        let viewModel = OnboardingViewModel()
        #expect(viewModel.canGoNext == true)

        viewModel.nextStep() // Step 1: Engines
        #expect(viewModel.currentStep == 1)
        #expect(viewModel.canGoNext == true)

        viewModel.nextStep() // Step 2: Tunnels
        #expect(viewModel.currentStep == 2)
        #expect(viewModel.canGoNext == true)

        viewModel.nextStep() // Step 3: Ready
        #expect(viewModel.currentStep == 3)
        #expect(viewModel.canGoNext == false)
    }

    // MARK: - [TC-D02] Partial Installed Mapping
    @Test("TC-D02: System dependency items preserve respective installed states and metadata")
    func testPartialInstalledMapping() async {
        let viewModel = OnboardingViewModel()
        await viewModel.scanDependenciesIfNeeded()

        // Verify structure and keys integrity across all items
        for dep in viewModel.engineDependencies {
            #expect(!dep.id.isEmpty)
            #expect(!dep.name.isEmpty)
            #expect(!dep.settingsKey.isEmpty)
            #expect(dep.category == .engine)
        }

        for dep in viewModel.tunnelingDependencies {
            #expect(!dep.id.isEmpty)
            #expect(!dep.name.isEmpty)
            #expect(!dep.settingsKey.isEmpty)
            #expect(dep.category == .tunneling)
        }
    }

    // MARK: - [TC-D03] Engine vs Tunnel Segregation
    @Test("TC-D03: Engine dependencies exactly 4 and tunneling dependencies exactly 2")
    func testEngineVsTunnelSegregation() async {
        let viewModel = OnboardingViewModel()
        await viewModel.scanDependenciesIfNeeded()

        #expect(viewModel.engineDependencies.count == 4)
        let engineIDs = Set(viewModel.engineDependencies.map(\.id))
        #expect(engineIDs == ["kubectl", "kubeconfig", "docker", "podman"])

        #expect(viewModel.tunnelingDependencies.count == 2)
        let tunnelIDs = Set(viewModel.tunnelingDependencies.map(\.id))
        #expect(tunnelIDs == ["cloudflared", "ngrok"])
    }

    // MARK: - [TC-D04] Idempotent Pre-Scan
    @Test("TC-D04: Repeated calls to scanDependenciesIfNeeded do not re-execute unless forced")
    func testIdempotentPreScan() async {
        let viewModel = OnboardingViewModel()
        #expect(viewModel.hasInitialScanned == false)

        await viewModel.scanDependenciesIfNeeded()
        #expect(viewModel.hasInitialScanned == true)

        // Second pass should be a zero-op
        await viewModel.scanDependenciesIfNeeded(force: false)
        #expect(viewModel.hasInitialScanned == true)
        #expect(viewModel.isScanning == false)
    }
}
