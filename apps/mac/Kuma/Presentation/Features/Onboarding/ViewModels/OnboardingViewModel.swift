import Foundation
import Observation
import os

@Observable
@MainActor
public final class OnboardingViewModel {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "OnboardingViewModel")

    public var currentStep: Int = 0
    public var isScanning: Bool = false
    public var hasInitialScanned: Bool = false

    public var engineDependencies: [SystemDependency] = []
    public var tunnelingDependencies: [SystemDependency] = []

    /// Transient validation error to show alert/popover when user picks an invalid binary file
    public var pathValidationError: String? = nil

    public let totalSteps: Int = 4 // 0: Welcome, 1: Engines, 2: Tunneling, 3: Ready

    /// Single background scan task reference to prevent overlapping/concurrent scans (race conditions)
    private var scanTask: Task<Void, Never>? = nil
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var canGoNext: Bool {
        currentStep < totalSteps - 1
    }

    public var canGoPrev: Bool {
        currentStep > 0
    }

    /// Performs dependency scan only if not already scanned or when explicitly requested.
    public func scanDependenciesIfNeeded(force: Bool = false) async {
        guard !hasInitialScanned || force else { return }
        await runScan(isManualRescan: force)
    }

    /// Executes system scan across all CLI engines and tunneling tools in a single unified, cancellable pass.
    public func runScan(isManualRescan: Bool = false) async {
        // Cancel any pending/running scan task to ensure atomic state resolution
        scanTask?.cancel()
        self.isScanning = true

        let task = Task { @MainActor [weak self] () -> Void in
            guard let self else { return }

            let customKubectl = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customKubectlPath,
                fallbackKey: KumaSettingsKey.legacyKubectlPath,
                defaults: self.userDefaults
            )
            let customKubeconfig = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customKubeconfigPath,
                fallbackKey: KumaSettingsKey.legacyKubeconfigPath,
                defaults: self.userDefaults
            )
            let customDocker = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customDockerPath,
                fallbackKey: KumaSettingsKey.legacyDockerPath,
                defaults: self.userDefaults
            )
            let customPodman = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customPodmanPath,
                fallbackKey: KumaSettingsKey.legacyPodmanPath,
                defaults: self.userDefaults
            )
            let customCloudflared = KumaSettingsKey.string(
                forKey: KumaSettingsKey.cloudflaredPath,
                fallbackKey: KumaSettingsKey.legacyCloudflaredPath,
                defaults: self.userDefaults
            )
            let customNgrok = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customNgrokPath,
                fallbackKey: KumaSettingsKey.legacyNgrokPath,
                defaults: self.userDefaults
            )

            async let kubectlPath = DependencyChecker.resolvedPath(for: "kubectl", customPath: customKubectl)
            async let dockerPath = DependencyChecker.resolvedPath(for: "docker", customPath: customDocker)
            async let podmanPath = DependencyChecker.resolvedPath(for: "podman", customPath: customPodman)
            async let cloudflaredPath = DependencyChecker.resolvedPath(for: "cloudflared", customPath: customCloudflared)
            async let ngrokPath = DependencyChecker.resolvedPath(for: "ngrok", customPath: customNgrok)
            let isKubeconfigPresent = DependencyChecker.isKubeconfigPresent(customPath: customKubeconfig)

            let paths = await (kubectlPath, dockerPath, podmanPath, cloudflaredPath, ngrokPath)

            guard !Task.isCancelled else {
                Self.logger.debug("Onboarding scan task was cancelled before applying state")
                self.isScanning = false
                return
            }

            if isManualRescan {
                // Tactile feedback delay on manual button click
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            guard !Task.isCancelled else {
                self.isScanning = false
                return
            }

            self.engineDependencies = [
                SystemDependency(
                    id: "kubectl",
                    name: "Kubernetes CLI (kubectl)",
                    iconName: "network",
                    isInstalled: paths.0 != nil,
                    path: paths.0,
                    category: .engine,
                    description: "Enables Kubernetes provider",
                    settingsKey: KumaSettingsKey.customKubectlPath
                ),
                SystemDependency(
                    id: "kubeconfig",
                    name: "Kubeconfig File",
                    iconName: "doc.text.fill",
                    isInstalled: isKubeconfigPresent,
                    path: isKubeconfigPresent ? (customKubeconfig ?? "~/.kube/config") : nil,
                    category: .engine,
                    description: "Cluster configuration for Kubernetes",
                    settingsKey: KumaSettingsKey.customKubeconfigPath
                ),
                SystemDependency(
                    id: "docker",
                    name: "Docker Engine",
                    iconName: "shippingbox.fill",
                    isInstalled: paths.1 != nil,
                    path: paths.1,
                    category: .engine,
                    description: "Enables Docker provider",
                    settingsKey: KumaSettingsKey.customDockerPath
                ),
                SystemDependency(
                    id: "podman",
                    name: "Podman Engine",
                    iconName: "cylinder.split.1x2.fill",
                    isInstalled: paths.2 != nil,
                    path: paths.2,
                    category: .engine,
                    description: "Enables Podman provider",
                    settingsKey: KumaSettingsKey.customPodmanPath
                )
            ]

            self.tunnelingDependencies = [
                SystemDependency(
                    id: "cloudflared",
                    name: "Cloudflare Tunnel (cloudflared)",
                    iconName: "cloud.bolt.fill",
                    isInstalled: paths.3 != nil,
                    path: paths.3,
                    category: .tunneling,
                    description: "Enables Tunnel via Cloudflare",
                    settingsKey: KumaSettingsKey.cloudflaredPath
                ),
                SystemDependency(
                    id: "ngrok",
                    name: "ngrok Tunnel",
                    iconName: "globe",
                    isInstalled: paths.4 != nil,
                    path: paths.4,
                    category: .tunneling,
                    description: "Enables Tunnel via ngrok",
                    settingsKey: KumaSettingsKey.customNgrokPath
                )
            ]

            self.hasInitialScanned = true
            self.isScanning = false
        }

        self.scanTask = task
        await task.value
    }

    /// Validates and sets custom override path for a given dependency.
    /// Rejects invalid files with user-facing validation error and aborts persistence.
    @discardableResult
    public func setCustomPath(for dependency: SystemDependency, path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // User cleared path -> save empty string to reset to system default
            self.userDefaults.set("", forKey: dependency.settingsKey)
            self.pathValidationError = nil
            Task { await runScan(isManualRescan: false) }
            return true
        }

        // Validate binary / file depending on dependency type
        if dependency.id == "kubeconfig" {
            let nsPath = NSString(string: trimmed).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: nsPath) {
                self.pathValidationError = "Selected kubeconfig file does not exist at specified path."
                return false
            }
        } else {
            let validation = DependencyChecker.validateCustomBinary(path: trimmed, expectedCommand: dependency.id)
            if !validation.isValid {
                self.pathValidationError = validation.errorMessage ?? "Selected file is not a valid executable binary for \(dependency.name)."
                return false
            }
        }

        // Valid -> persist to standardized settings key and trigger atomic re-scan
        self.pathValidationError = nil
        self.userDefaults.set(trimmed, forKey: dependency.settingsKey)

        self.scanTask = Task {
            await runScan(isManualRescan: false)
        }
        return true
    }

    /// Awaits any in-flight scan task to finish cleanly (zero race conditions for testing & UI).
    public func waitForPendingScan() async {
        await self.scanTask?.value
    }

    public func clearValidationError() {
        self.pathValidationError = nil
    }

    public func nextStep() {
        guard canGoNext else { return }
        currentStep += 1
    }

    public func prevStep() {
        guard canGoPrev else { return }
        currentStep -= 1
    }
}
