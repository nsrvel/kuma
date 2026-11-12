import SwiftUI
import UniformTypeIdentifiers

public struct SettingsTunnelingToolsSection: View {
    @Bindable var viewModel: SettingsViewModel

    // Auto-detected default paths when custom path is empty
    @State private var defaultCloudflaredPath: String = ""
    @State private var defaultNgrokPath: String = ""

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Validation Computations (Zero-latency)

    private var cloudflaredValidation: BinaryValidationResult {
        DependencyChecker.validateCustomBinary(path: viewModel.cloudflaredPath, expectedCommand: "cloudflared")
    }

    private var ngrokValidation: BinaryValidationResult {
        DependencyChecker.validateCustomBinary(path: viewModel.customNgrokPath, expectedCommand: "ngrok")
    }

    public var body: some View {
        KumaFormSection(
            icon: "cloud.bolt.fill",
            title: "Tunneling Tools"
        ) {
            VStack(alignment: .leading, spacing: KumaSpacing.lg) {
                // Cloudflare Tunnel
                VStack(alignment: .leading, spacing: KumaSpacing.sm) {
                    Text("Cloudflare Tunnel (cloudflared)")
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    KumaFilePickerField(
                        label: "",
                        path: $viewModel.cloudflaredPath,
                        placeholder: defaultCloudflaredPath.isEmpty ? "Not detected" : defaultCloudflaredPath,
                        chooseFiles: true,
                        chooseDirectories: false,
                        allowedContentTypes: [.unixExecutable, .executable],
                        error: cloudflaredValidation.errorMessage
                    )
                }

                Divider().opacity(0.3)

                // ngrok Tunnel
                VStack(alignment: .leading, spacing: KumaSpacing.sm) {
                    Text("ngrok")
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)

                    KumaFilePickerField(
                        label: "",
                        path: $viewModel.customNgrokPath,
                        placeholder: defaultNgrokPath.isEmpty ? "Not detected" : defaultNgrokPath,
                        chooseFiles: true,
                        chooseDirectories: false,
                        allowedContentTypes: [.unixExecutable, .executable],
                        error: ngrokValidation.errorMessage
                    )
                }
            }
        }
        .task {
            await refreshTunnelPaths()
        }
    }

    private func refreshTunnelPaths() async {
        let resolver = EnvironmentPathResolver.shared
        let cf = await resolver.resolveExecutablePath(for: "cloudflared")
        let ng = await resolver.resolveExecutablePath(for: "ngrok")
        await MainActor.run {
            self.defaultCloudflaredPath = cf ?? ""
            self.defaultNgrokPath = ng ?? ""

            // Populate detected paths as active concrete values if field is currently unconfigured
            if viewModel.cloudflaredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let cf {
                viewModel.cloudflaredPath = cf
            }
            if viewModel.customNgrokPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let ng {
                viewModel.customNgrokPath = ng
            }
        }
    }
}

