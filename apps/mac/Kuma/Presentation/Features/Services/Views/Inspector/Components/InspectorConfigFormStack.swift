import SwiftUI

/// Form stack container for Service Inspector's single unified scrollable configuration view.
public struct InspectorConfigFormStack: View {
    @Environment(ServiceStateStore.self) private var serviceStateStore

    public let serviceID: UUID
    public let isLocked: Bool
    public let isRunning: Bool
    public let inspectorVM: ServiceInspectorViewModel
    public let service: Service

    public init(
        serviceID: UUID,
        isLocked: Bool,
        isRunning: Bool,
        inspectorVM: ServiceInspectorViewModel,
        service: Service
    ) {
        self.serviceID = serviceID
        self.isLocked = isLocked
        self.isRunning = isRunning
        self.inspectorVM = inspectorVM
        self.service = service
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorRunningBanner(
                    runtime: ServiceRuntimeState(executionState: inspectorVM.executionState),
                    isDisabled: service.isDisabled,
                    crashDetail: serviceStateStore.lastFailure(for: serviceID),
                    configurationIssues: inspectorVM.configurationIssues,
                    onViewLogs: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            inspectorVM.isViewingLogs = true
                        }
                    }
                )

                // 1. General Identification Form
                ServiceGeneralSettingsView(
                    name: Binding(
                        get: { inspectorVM.service?.name ?? "" },
                        set: {
                            inspectorVM.service?.name = $0
                            inspectorVM.scheduleAutoSave()
                        }
                    ),
                    serviceDescription: Binding(
                        get: { inspectorVM.service?.description ?? "" },
                        set: {
                            inspectorVM.service?.description = $0.isEmpty ? nil : $0
                            inspectorVM.scheduleAutoSave()
                        }
                    ),
                    placeholder: "Postgres DB",
                    icon: "info.circle",
                    subtitle: "Service name and purpose"
                )
                .disabled(isLocked)

                // 2. Providers Section (Selector + Inline Add/Edit)
                ServiceProvidersSectionView(
                    serviceID: serviceID,
                    providers: inspectorVM.providers,
                    activeProviderID: inspectorVM.activeProviderID,
                    isLocked: isLocked,
                    onSelectProvider: { newID in
                        inspectorVM.switchProvider(to: newID)
                    },
                    onAddProvider: { newProvider in
                        inspectorVM.addProvider(newProvider)
                    },
                    onUpdateProvider: { updatedProvider in
                        inspectorVM.updateProviderDirectly(updatedProvider)
                    },
                    onDeleteProvider: { provider in
                        inspectorVM.deleteProvider(provider)
                    }
                )

                // 3. Active Provider Configuration Form
                if let activeProviderID = inspectorVM.activeProviderID {
                    InspectorFormSections(
                        provider: activeProviderBinding(activeProviderID: activeProviderID),
                        ports: Binding(
                            get: { inspectorVM.draftPorts },
                            set: { inspectorVM.draftPorts = $0 }
                        ),
                        sshAuthType: Binding(
                            get: { inspectorVM.sshAuthType },
                            set: { inspectorVM.sshAuthType = $0 }
                        ),
                        kubeConfigVM: inspectorVM.kubeConfigVM,
                        serviceID: serviceID,
                        isRunning: isRunning,
                        isLocked: isLocked,
                        onFieldChanged: {
                            inspectorVM.scheduleAutoSave()
                        },
                        onPortsChanged: {
                            inspectorVM.scheduleAutoSave(portsTouched: true)
                        }
                    )
                }

                // 4. Options Section (Auto reconnect, disable, delete)
                InspectorOptionsSection(
                    activeProvider: inspectorVM.activeProviderID.map { activeProviderBinding(activeProviderID: $0) },
                    isLocked: isLocked,
                    onProviderFieldChanged: {
                        inspectorVM.scheduleAutoSave()
                    },
                    isDisabled: Binding(
                        get: { inspectorVM.service?.isDisabled ?? false },
                        set: { newValue in
                            inspectorVM.toggleDisabled(newValue)
                        }
                    ),
                    isRunning: isRunning,
                    onDelete: {
                        inspectorVM.showDeleteConfirmation = true
                    }
                )
            }
            .padding(KumaSpacing.lg)
        }
    }

    private func activeProviderBinding(activeProviderID: UUID) -> Binding<Provider> {
        Binding(
            get: {
                if let idx = inspectorVM.providers.firstIndex(where: { $0.id == activeProviderID }) {
                    return inspectorVM.providers[idx]
                }
                // ponytail: providers can swap mid-frame during loadService; avoid stale index crash
                return Provider(
                    id: activeProviderID,
                    serviceID: serviceID,
                    type: inspectorVM.activeCategory
                )
            },
            set: { newValue in
                guard let idx = inspectorVM.providers.firstIndex(where: { $0.id == activeProviderID }) else { return }
                inspectorVM.providers[idx] = newValue
            }
        )
    }
}
