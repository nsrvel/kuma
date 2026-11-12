import SwiftUI

public struct InspectorFormSections: View {
    @Binding public var provider: Provider
    @Binding public var ports: [KumaPortMappingItem]
    @Binding public var sshAuthType: SSHAuthType
    public var kubeConfigVM: KubeConfigViewModel?
    public let serviceID: UUID
    public let isRunning: Bool
    public let isLocked: Bool
    public let onFieldChanged: () -> Void
    public let onPortsChanged: () -> Void

    public init(
        provider: Binding<Provider>,
        ports: Binding<[KumaPortMappingItem]>,
        sshAuthType: Binding<SSHAuthType>,
        kubeConfigVM: KubeConfigViewModel? = nil,
        serviceID: UUID = UUID(),
        isRunning: Bool = false,
        isLocked: Bool = false,
        onFieldChanged: @escaping () -> Void = {},
        onPortsChanged: @escaping () -> Void = {}
    ) {
        self._provider = provider
        self._ports = ports
        self._sshAuthType = sshAuthType
        self.kubeConfigVM = kubeConfigVM
        self.serviceID = serviceID
        self.isRunning = isRunning
        self.isLocked = isLocked
        self.onFieldChanged = onFieldChanged
        self.onPortsChanged = onPortsChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch provider.type {
            case .kubernetes:
                InspectorKubernetesFormSection(
                    provider: $provider,
                    kubeConfigVM: kubeConfigVM,
                    serviceID: serviceID,
                    isRunning: isRunning,
                    isLocked: isLocked,
                    onFieldChanged: onFieldChanged
                )

            case .docker:
                InspectorComposeFormSection(
                    provider: $provider,
                    isLocked: isLocked,
                    isPodman: false,
                    onFieldChanged: onFieldChanged
                )

            case .podman:
                InspectorComposeFormSection(
                    provider: $provider,
                    isLocked: isLocked,
                    isPodman: true,
                    onFieldChanged: onFieldChanged
                )

            case .shell, .ssh, .httpCheck, .tunnel, .processMonitor:
                InspectorRemoteAndNetworkFormSections(
                    provider: $provider,
                    sshAuthType: $sshAuthType,
                    isLocked: isLocked,
                    onFieldChanged: onFieldChanged
                )
            }

            if provider.type == .kubernetes || provider.type == .ssh {
                KumaFormSection(icon: "arrow.left.arrow.right", title: "Ports") {
                    KumaPortMappingEditor(label: "", items: $ports)
                        .disabled(isLocked)
                        .onChange(of: ports) { _, _ in
                            onPortsChanged()
                        }
                }
            }
        }
    }
}
