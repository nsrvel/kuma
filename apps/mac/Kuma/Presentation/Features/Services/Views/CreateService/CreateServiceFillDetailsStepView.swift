import SwiftUI

public struct CreateServiceFillDetailsStepView: View {
    public let selectedProvider: ProviderCategory
    @Binding public var generalDraft: ServiceGeneralDraft
    @Binding public var kubeDraft: ServiceKubernetesDraft
    public var kubeConfigVM: KubeConfigViewModel
    @Binding public var dockerDraft: ServiceComposeDraft
    @Binding public var podmanDraft: ServiceComposeDraft
    @Binding public var shellDraft: ServiceShellDraft
    @Binding public var sshDraft: ServiceSSHDraft
    @Binding public var sshAuthType: SSHAuthType
    @Binding public var sshKeyPath: String
    @Binding public var sshPassword: String
    @Binding public var healthCheckDraft: ServiceHealthCheckDraft
    @Binding public var tunnelDraft: ServiceTunnelDraft
    @Binding public var monitorDraft: ServiceProcessMonitorDraft
    @Binding public var temporaryPorts: [KumaPortMappingItem]

    public var isFormValid: Bool
    public var isSaving: Bool
    public let onBack: () -> Void
    public let onCancel: () -> Void
    public let onCreate: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Button {
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to Provider selection")

                        Text("Service Details (\(selectedProvider.sidebarLabel))")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .padding(.top, 16)

                    ServiceGeneralSettingsView(
                        name: $generalDraft.name,
                        serviceDescription: $generalDraft.description,
                        placeholder: placeholderName
                    )

                    CreateServiceContextualFormView(
                        selectedProvider: selectedProvider,
                        kubeDraft: $kubeDraft,
                        kubeConfigVM: kubeConfigVM,
                        dockerDraft: $dockerDraft,
                        podmanDraft: $podmanDraft,
                        shellDraft: $shellDraft,
                        sshDraft: $sshDraft,
                        sshAuthType: $sshAuthType,
                        sshKeyPath: $sshKeyPath,
                        sshPassword: $sshPassword,
                        healthCheckDraft: $healthCheckDraft,
                        tunnelDraft: $tunnelDraft,
                        monitorDraft: $monitorDraft
                    )

                    if selectedProvider == .kubernetes || selectedProvider == .ssh {
                        KumaFormSection(icon: "arrow.left.arrow.right", title: "Ports") {
                            KumaPortMappingEditor(label: "", items: $temporaryPorts)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Divider().opacity(0.4)

            HStack {
                Button("Back") { onBack() }

                Spacer()

                Button("Cancel") { onCancel() }
                    .padding(.trailing, 8)

                Button("Create") { onCreate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid || isSaving)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var placeholderName: String {
        switch selectedProvider {
        case .kubernetes: return "PostgreSQL Database"
        case .docker, .podman: return "Redis Cache"
        case .shell: return "Frontend Dev Server"
        case .ssh: return "Staging Bastion Tunnel"
        case .httpCheck: return "Auth Service Health"
        case .tunnel: return "Webhook Public Tunnel"
        case .processMonitor: return "Redis Server Monitor"
        }
    }
}
