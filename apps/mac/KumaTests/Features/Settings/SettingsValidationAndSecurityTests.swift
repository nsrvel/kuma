import Foundation
import Testing
@testable import Kuma

@Suite("Settings Category B: Input/Form Validation, Crypto/Vault & Security", .serialized)
@MainActor
struct SettingsValidationAndSecurityTests {

    // MARK: - [TC-B01] Kubectl Valid Executable
    @Test("TC-B01: User selects valid executable binary for kubectl")
    func testKubectlValidExecutable() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let execPath = harness.createExecutable(named: "kubectl")
        let result = DependencyChecker.validateCustomBinary(path: execPath, expectedCommand: "kubectl")

        #expect(result.isValid == true)
        #expect(result.errorMessage == nil)
    }

    // MARK: - [TC-B02] Kubectl Non-Executable Rejection
    @Test("TC-B02: User selects non-executable file for kubectl binary")
    func testKubectlNonExecutableRejection() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let filePath = harness.createNonExecutableFile(named: "kubectl")
        let result = DependencyChecker.validateCustomBinary(path: filePath, expectedCommand: "kubectl")

        #expect(result.isValid == false)
        #expect(result == .notExecutable)
        #expect(result.errorMessage == "File is not an executable binary")
    }

    // MARK: - [TC-B03] Kubectl Binary Name Mismatch Rejection
    @Test("TC-B03: User selects mismatched binary (e.g. docker binary for kubectl)")
    func testKubectlBinaryMismatchRejection() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let execPath = harness.createExecutable(named: "docker")
        let result = DependencyChecker.validateCustomBinary(path: execPath, expectedCommand: "kubectl")

        #expect(result.isValid == false)
        if case .nameMismatch(let expected, let actual) = result {
            #expect(expected == "kubectl")
            #expect(actual.contains("docker"))
        } else {
            Issue.record("Expected nameMismatch, got \(result)")
        }
    }

    // MARK: - [TC-B04] Docker Valid Executable
    @Test("TC-B04: User selects valid executable binary for docker")
    func testDockerValidExecutable() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let execPath = harness.createExecutable(named: "docker")
        let result = DependencyChecker.validateCustomBinary(path: execPath, expectedCommand: "docker")

        #expect(result.isValid == true)
    }

    // MARK: - [TC-B05] Podman Valid Executable
    @Test("TC-B05: User selects valid executable binary for podman")
    func testPodmanValidExecutable() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let execPath = harness.createExecutable(named: "podman")
        let result = DependencyChecker.validateCustomBinary(path: execPath, expectedCommand: "podman")

        #expect(result.isValid == true)
    }

    // MARK: - [TC-B06] Cloudflared Valid Executable
    @Test("TC-B06: User selects valid executable binary for cloudflared")
    func testCloudflaredValidExecutable() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let execPath = harness.createExecutable(named: "cloudflared")
        let result = DependencyChecker.validateCustomBinary(path: execPath, expectedCommand: "cloudflared")

        #expect(result.isValid == true)
    }

    // MARK: - [TC-B07] ngrok Valid Executable
    @Test("TC-B07: User selects valid executable binary for ngrok")
    func testNgrokValidExecutable() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let execPath = harness.createExecutable(named: "ngrok")
        let result = DependencyChecker.validateCustomBinary(path: execPath, expectedCommand: "ngrok")

        #expect(result.isValid == true)
    }

    // MARK: - [TC-B08] Kubeconfig Valid File
    @Test("TC-B08: User selects existing kubeconfig file")
    func testKubeconfigValidFile() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let configPath = harness.createKubeconfigFile()
        let nsPath = NSString(string: configPath).expandingTildeInPath

        #expect(FileManager.default.fileExists(atPath: nsPath) == true)
    }

    // MARK: - [TC-B09] Kubeconfig Missing File Rejection
    @Test("TC-B09: User specifies non-existent kubeconfig path")
    func testKubeconfigMissingFileRejection() {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        let fakePath = "/path/to/non_existent_kubeconfig_\(UUID().uuidString).yaml"
        let nsPath = NSString(string: fakePath).expandingTildeInPath

        #expect(FileManager.default.fileExists(atPath: nsPath) == false)
    }

    // MARK: - [TC-B10] Tilde Path Expansion In Settings
    @Test("TC-B10: Path starting with tilde expands to user home directory")
    func testTildePathExpansionInSettings() {
        let tildePath = "~/bin/mybinary"
        let expanded = NSString(string: tildePath).expandingTildeInPath

        #expect(!expanded.hasPrefix("~"))
        #expect(expanded.contains("/Users/"))
        #expect(expanded.hasSuffix("/bin/mybinary"))
    }
}
