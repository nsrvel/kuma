import Foundation
import Testing
@testable import Kuma

@Suite("Onboarding Category B: Binary Validation & Custom Path Inputs", .serialized)
@MainActor
struct OnboardingBinaryValidationTests {

    // MARK: - [TC-B01] File Not Found Rejection
    @Test("TC-B01: Path to non-existent file is rejected and storage remains unmutated")
    func testFileNotFoundRejection() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "kubectl",
            name: "Kubernetes CLI",
            iconName: "network",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customKubectlPath
        )

        let nonExistentPath = "/usr/local/bin/non_existent_binary_\(UUID().uuidString)"
        let success = viewModel.setCustomPath(for: dep, path: nonExistentPath)

        #expect(success == false)
        #expect(viewModel.pathValidationError?.contains("File does not exist") == true)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customKubectlPath) != nonExistentPath)
    }

    // MARK: - [TC-B02] Directory Path Rejection
    @Test("TC-B02: Selecting a directory folder instead of a binary file is rejected as notExecutable")
    func testDirectorySelectionRejection() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let tempDir = harness.createTempDirectory(named: "kubectl_dir")
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "kubectl",
            name: "Kubernetes CLI",
            iconName: "network",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customKubectlPath
        )

        let success = viewModel.setCustomPath(for: dep, path: tempDir)
        #expect(success == false)
        #expect(viewModel.pathValidationError?.contains("not an executable") == true)
    }

    // MARK: - [TC-B03] Non-Executable File Rejection
    @Test("TC-B03: Plain text file without executable permissions is rejected")
    func testNonExecutableFileRejection() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let textFile = harness.createNonExecutableFile(named: "kubectl")
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "kubectl",
            name: "Kubernetes CLI",
            iconName: "network",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customKubectlPath
        )

        let success = viewModel.setCustomPath(for: dep, path: textFile)
        #expect(success == false)
        #expect(viewModel.pathValidationError?.contains("not an executable") == true)
    }

    // MARK: - [TC-B04] Binary Name Mismatch Rejection
    @Test("TC-B04: Selecting docker binary for kubectl requirement is rejected with name mismatch")
    func testBinaryNameMismatchRejection() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let dockerBinary = harness.createDummyExecutable(named: "docker")
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "kubectl",
            name: "Kubernetes CLI",
            iconName: "network",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customKubectlPath
        )

        let success = viewModel.setCustomPath(for: dep, path: dockerBinary)
        #expect(success == false)
        #expect(viewModel.pathValidationError?.contains("does not match") == true)
    }

    // MARK: - [TC-B05] Tilde Path Expansion
    @Test("TC-B05: Inputting path with tilde expands correctly to home directory")
    func testTildePathExpansion() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        // Create executable in user's home directory with automatic tracking for cleanup
        let created = harness.createHomeExecutable(named: "kubectl")
        let tildePath = created.tildePath

        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "kubectl",
            name: "Kubernetes CLI",
            iconName: "network",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customKubectlPath
        )

        let success = viewModel.setCustomPath(for: dep, path: tildePath)
        #expect(success == true)
        #expect(viewModel.pathValidationError == nil)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customKubectlPath) == tildePath)
    }

    // MARK: - [TC-B06] Whitespace Trimmed Path
    @Test("TC-B06: Raw path with surrounding whitespace is automatically trimmed and saved")
    func testWhitespaceTrimmedPath() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let binaryPath = harness.createDummyExecutable(named: "docker")
        let paddedPath = "   \(binaryPath)   \n"
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "docker",
            name: "Docker Engine",
            iconName: "shippingbox.fill",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customDockerPath
        )

        let success = viewModel.setCustomPath(for: dep, path: paddedPath)
        #expect(success == true)
        #expect(viewModel.pathValidationError == nil)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customDockerPath) == binaryPath)
    }

    // MARK: - [TC-B07] Clearing Custom Path
    @Test("TC-B07: Clearing path with empty string resets settings key and invokes auto-scan")
    func testClearingCustomPath() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "podman",
            name: "Podman Engine",
            iconName: "cylinder.split.1x2.fill",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customPodmanPath
        )

        let success = viewModel.setCustomPath(for: dep, path: "")
        #expect(success == true)
        #expect(viewModel.pathValidationError == nil)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customPodmanPath) == "")
    }

    // MARK: - [TC-B08] Kubeconfig YAML Validation
    @Test("TC-B08: Valid YAML file is accepted for kubeconfig without requiring executable permission")
    func testKubeconfigYamlValidation() {
        let harness = OnboardingTestHarness()
        defer { harness.cleanup() }

        let yamlFile = harness.createDummyKubeconfig()
        let viewModel = OnboardingViewModel(userDefaults: harness.userDefaults)
        let dep = SystemDependency(
            id: "kubeconfig",
            name: "Kubeconfig File",
            iconName: "doc.text.fill",
            isInstalled: false,
            settingsKey: KumaSettingsKey.customKubeconfigPath
        )

        let success = viewModel.setCustomPath(for: dep, path: yamlFile)
        #expect(success == true)
        #expect(viewModel.pathValidationError == nil)
        #expect(harness.userDefaults.string(forKey: KumaSettingsKey.customKubeconfigPath) == yamlFile)
    }
}
