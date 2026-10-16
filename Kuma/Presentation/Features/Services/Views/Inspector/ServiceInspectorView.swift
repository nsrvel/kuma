import SwiftUI

public struct ServiceInspectorView: View {
    public let serviceID: UUID
    public let workspaceID: UUID
    @State private var inspectorVM: ServiceInspectorViewModel
    @Environment(ServiceStateStore.self) var serviceStateStore

    private var blockingConfigurationMessages: [String] {
        inspectorVM.configurationIssues
            .filter { $0.severity == .blocking }
            .map(\.message)
    }

    public init(
        serviceID: UUID,
        workspaceID: UUID,
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository(),
        stateStore: ServiceStateStore? = nil
    ) {
        self.serviceID = serviceID
        self.workspaceID = workspaceID
        _inspectorVM = State(initialValue: ServiceInspectorViewModel(
            serviceID: serviceID,
            workspaceID: workspaceID,
            serviceRepository: serviceRepository,
            stateStore: stateStore
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let service = inspectorVM.service {
                let isSynced = service.id == serviceID
                let showStaleShell = !isSynced && inspectorVM.isLoadingServiceDetail
                if isSynced || showStaleShell {
                let executionState = serviceStateStore.state(for: serviceID)
                let isRunning = executionState.isOperational
                let isLocked = service.isDisabled || isRunning || executionState == .starting

                let isViewingLogs = inspectorVM.isViewingLogs

                InspectorStatusHeader(
                    service: service,
                    provider: inspectorVM.activeProvider,
                    runtime: ServiceRuntimeState(executionState: executionState),
                    isViewingLogs: isViewingLogs,
                    isStartDisabled: !inspectorVM.canStartService,
                    onToggle: {
                        inspectorVM.toggleRunning()
                    },
                    onBack: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            inspectorVM.isViewingLogs = false
                        }
                    }
                )
                .allowsHitTesting(isSynced)

                Divider()
                    .padding(.horizontal, KumaSpacing.lg)

                Group {
                    if isViewingLogs {
                        InspectorLiveConsoleView(
                            serviceID: serviceID,
                            isRunning: isRunning,
                            lastFailure: serviceStateStore.lastFailure(for: serviceID),
                            configurationMessages: blockingConfigurationMessages
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .trailing))
                        ))
                    } else {
                        InspectorConfigFormStack(
                            serviceID: serviceID,
                            isLocked: isLocked,
                            isRunning: isRunning,
                            inspectorVM: inspectorVM,
                            service: service
                        )
                    }
                }
                .opacity(isSynced ? 1 : 0.88)
                .allowsHitTesting(isSynced)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isViewingLogs)
                }
            } else if inspectorVM.isLoadingServiceDetail {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading service…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                KumaEmptyStateView(
                    iconName: "sidebar.right",
                    title: "No Selection",
                    description: "Select a service to view configuration details."
                )
            }
        }
        .onChange(of: serviceID) { _, newID in
            if inspectorVM.service?.id != newID {
                inspectorVM.isLoadingServiceDetail = true
                inspectorVM.isViewingLogs = false
                inspectorVM.clearConfigurationValidationState()
            }
        }
        .task(id: serviceID) {
            inspectorVM.stateStore = serviceStateStore
            await inspectorVM.loadService(id: serviceID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kumaServiceUpdated)) { notif in
            if (notif.userInfo?[KumaServiceNotification.sourceKey] as? String) == KumaServiceNotification.sourceInspector {
                return
            }
            guard let changedID = notif.object as? UUID, changedID == serviceID else { return }
            Task { await inspectorVM.loadService(id: serviceID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kumaGroupsUpdated)) { _ in
            Task { await inspectorVM.loadService(id: serviceID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kumaServiceDeleted)) { notif in
            guard let deletedID = notif.object as? UUID, deletedID == serviceID else { return }
            inspectorVM.clearAfterExternalDeletion()
        }
        .onDisappear {
            Task { await inspectorVM.flushPendingAutoSave() }
        }
        .confirmationDialog(
            "Delete Service?",
            isPresented: $inspectorVM.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                inspectorVM.deleteService()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("‘\(inspectorVM.service?.name ?? "Service")’ and its configurations will be permanently deleted.")
        }
    }
}
