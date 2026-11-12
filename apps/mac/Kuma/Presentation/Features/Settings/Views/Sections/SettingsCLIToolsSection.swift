import SwiftUI
import UniformTypeIdentifiers

public struct SettingsCLIToolsSection: View {
    @Bindable var viewModel: SettingsViewModel

    // Auto-detected default paths when custom path is empty
    @State private var defaultDockerPath: String = ""
    @State private var defaultKubectlPath: String = ""
    @State private var defaultPodmanPath: String = ""

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Validation Computations (Zero-latency)

    private var kubectlValidation: BinaryValidationResult {
        DependencyChecker.validateCustomBinary(path: viewModel.customKubectlPath, expectedCommand: "kubectl")
    }

    private var kubeconfigValidation: String? {
        let trimmed = viewModel.customKubeconfigPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nsPath = NSString(string: trimmed).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: nsPath) {
            return "Configuration file does not exist at specified path"
        }
        return nil
    }

    private var dockerValidation: BinaryValidationResult {
        DependencyChecker.validateCustomBinary(path: viewModel.customDockerPath, expectedCommand: "docker")
    }

    private var podmanValidation: BinaryValidationResult {
        DependencyChecker.validateCustomBinary(path: viewModel.customPodmanPath, expectedCommand: "podman")
    }

    public var body: some View {
        KumaFormSection(
            icon: "terminal.fill",
            title: "CLI Tools"
        ) {
            VStack(alignment: .leading, spacing: KumaSpacing.lg) {
                // Kubectl
                VStack(alignment: .leading, spacing: KumaSpacing.sm) {
                    Text("Kubectl (kubectl)")
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    KumaFilePickerField(
                        label: "",
                        path: $viewModel.customKubectlPath,
                        placeholder: defaultKubectlPath.isEmpty ? "Not detected" : defaultKubectlPath,
                        chooseFiles: true,
                        chooseDirectories: false,
                        allowedContentTypes: [.unixExecutable, .executable],
                        error: kubectlValidation.errorMessage
                    )
                }

                Divider().opacity(0.3)

                // Default Kubeconfig Path
                VStack(alignment: .leading, spacing: KumaSpacing.sm) {
                    Text("Default Kubeconfig")
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    KumaFilePickerField(
                        label: "",
                        path: $viewModel.customKubeconfigPath,
                        placeholder: DependencyChecker.isKubeconfigPresent() ? "~/.kube/config" : "Not detected",
                        chooseFiles: true,
                        chooseDirectories: false,
                        error: kubeconfigValidation
                    )
                }

                Divider().opacity(0.3)

                // Docker
                VStack(alignment: .leading, spacing: KumaSpacing.sm) {
                    Text("Docker (docker)")
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    KumaFilePickerField(
                        label: "",
                        path: $viewModel.customDockerPath,
                        placeholder: defaultDockerPath.isEmpty ? "Not detected" : defaultDockerPath,
                        chooseFiles: true,
                        chooseDirectories: false,
                        allowedContentTypes: [.unixExecutable, .executable],
                        error: dockerValidation.errorMessage
                    )
                }

                Divider().opacity(0.3)

                // Podman
                VStack(alignment: .leading, spacing: KumaSpacing.sm) {
                    Text("Podman (podman)")
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    KumaFilePickerField(
                        label: "",
                        path: $viewModel.customPodmanPath,
                        placeholder: defaultPodmanPath.isEmpty ? "Not detected" : defaultPodmanPath,
                        chooseFiles: true,
                        chooseDirectories: false,
                        allowedContentTypes: [.unixExecutable, .executable],
                        error: podmanValidation.errorMessage
                    )
                }

                Divider().opacity(0.3)

                // Default Shell
                KumaRowPickerField(
                    label: "Default Shell",
                    description: "Shell used to execute custom scripts.",
                    options: DefaultShell.allCases.map(\.rawValue),
                    selection: $viewModel.defaultShell,
                    titleResolver: { (DefaultShell(rawValue: $0) ?? .zsh).label }
                )
            }
        }
        .task {
            await refreshDefaultPaths()
        }
    }

    private func refreshDefaultPaths() async {
        let resolver = EnvironmentPathResolver.shared
        let docker = await resolver.resolveExecutablePath(for: "docker")
        let kube = await resolver.resolveExecutablePath(for: "kubectl")
        let podman = await resolver.resolveExecutablePath(for: "podman")
        let kubeconfigExists = DependencyChecker.isKubeconfigPresent()

        await MainActor.run {
            self.defaultDockerPath = docker ?? ""
            self.defaultKubectlPath = kube ?? ""
            self.defaultPodmanPath = podman ?? ""

            // Populate detected paths as active concrete values if field is currently unconfigured
            if viewModel.customKubectlPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let kube {
                viewModel.customKubectlPath = kube
            }
            if viewModel.customDockerPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let docker {
                viewModel.customDockerPath = docker
            }
            if viewModel.customPodmanPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let podman {
                viewModel.customPodmanPath = podman
            }
            if viewModel.customKubeconfigPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kubeconfigExists {
                viewModel.customKubeconfigPath = "~/.kube/config"
            }
        }
    }
}

