import SwiftUI

public struct InspectorKubernetesFormSection: View {
    @Binding public var provider: Provider
    public var kubeConfigVM: KubeConfigViewModel?
    public let serviceID: UUID
    public let isRunning: Bool
    public let isLocked: Bool
    public let onFieldChanged: () -> Void

    private var liveResolvedTargetName: String? {
        guard isRunning else { return nil }
        return KubeLiveTargetDisplay.resolvedName(for: serviceID)
    }

    public var body: some View {
        Group {
            if let kubeConfigVM {
                KubeConfigConnectionView(
                    viewModel: kubeConfigVM,
                    isLocked: isLocked,
                    contextToTest: provider.kubeContext ?? "",
                    onConfigChanged: {
                        let sanitized = kubeConfigVM.sanitizedProviderContext(storedProviderContext: provider.kubeContext)
                        if provider.kubeContext != sanitized {
                            provider.kubeContext = sanitized
                        }
                        kubeConfigVM.testConnection(storedProviderContext: provider.kubeContext)
                        onFieldChanged()
                    }
                )
                .onChange(of: kubeConfigVM.isLoadingNamespaces) { _, _ in onFieldChanged() }
                .onChange(of: kubeConfigVM.connectionError) { _, _ in onFieldChanged() }
                .onChange(of: kubeConfigVM.connectionSuccess) { _, _ in onFieldChanged() }

                KumaFormSection(icon: "network", title: "Cluster Connection") {
                    KubeConnectionSettingsView(
                        kubeNamespace: Binding(
                            get: { provider.kubeNamespace ?? "" },
                            set: { provider.kubeNamespace = $0.isEmpty ? nil : $0; onFieldChanged() }
                        ),
                        kubeContext: Binding(
                            get: { provider.kubeContext ?? "" },
                            set: { newValue in
                                provider.kubeContext = newValue.isEmpty ? nil : newValue
                                onFieldChanged()
                                kubeConfigVM.testConnection(storedProviderContext: provider.kubeContext)
                            }
                        ),
                        availableContexts: kubeConfigVM.availableContexts
                    )
                    .disabled(isLocked)
                    .onChange(of: kubeConfigVM.availableContexts) { _, _ in
                        let sanitized = kubeConfigVM.sanitizedProviderContext(storedProviderContext: provider.kubeContext)
                        if provider.kubeContext != sanitized {
                            provider.kubeContext = sanitized
                            onFieldChanged()
                        }
                    }
                }
            }

            KumaFormSection(icon: "scope", title: "Target Resource") {
                KubeTargetSettingsView(
                    targetName: Binding(
                        get: { provider.targetName ?? "" },
                        set: { provider.targetName = $0.isEmpty ? nil : $0; onFieldChanged() }
                    ),
                    targetType: Binding(
                        get: { KubeTargetType(rawValue: provider.kubeTargetType ?? "") ?? .pod },
                        set: { provider.kubeTargetType = $0.rawValue; onFieldChanged() }
                    ),
                    usePattern: Binding(
                        get: { provider.usePattern ?? true },
                        set: { provider.usePattern = $0; onFieldChanged() }
                    ),
                    liveResolvedTargetName: liveResolvedTargetName
                )
                .disabled(isLocked)
            }
        }
    }
}
