import Combine
import SwiftUI

extension ServicesDeckView {
    @ViewBuilder
    func applyDeckNotificationHandlers<Content: View>(
        to content: Content,
        workspaceID: UUID
    ) -> some View {
        content
            .onReceive(Self.deckNotificationPublisher) { notif in
                handleDeckNotification(notif, workspaceID: workspaceID)
            }
    }

    private static var deckNotificationPublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .kumaServiceUpdated)
            .merge(with: NotificationCenter.default.publisher(for: .kumaServiceCreated))
            .merge(with: NotificationCenter.default.publisher(for: .kumaServiceDeleted))
            .merge(with: NotificationCenter.default.publisher(for: .kumaGroupsUpdated))
            .merge(with: NotificationCenter.default.publisher(for: .kumaFocusSearch))
            .merge(with: NotificationCenter.default.publisher(for: .kumaExportWorkspace))
            .merge(with: NotificationCenter.default.publisher(for: .kumaImportWorkspace))
            .eraseToAnyPublisher()
    }

    private func handleDeckNotification(_ notif: Notification, workspaceID: UUID) {
        switch notif.name {
        case .kumaServiceUpdated:
            if let sID = notif.object as? UUID {
                if (notif.userInfo?[KumaServiceNotification.sourceKey] as? String) == KumaServiceNotification.sourceDeck {
                    return
                }
                Task { await viewModel.refreshSingleServiceSnapshot(id: sID) }
            } else {
                viewModel.loadWorkspace(workspaceID: workspaceID)
            }
        case .kumaServiceCreated:
            if let sID = notif.object as? UUID {
                Task { await viewModel.refreshSingleServiceSnapshot(id: sID) }
            } else {
                viewModel.loadWorkspace(workspaceID: workspaceID)
            }
        case .kumaServiceDeleted:
            if let deletedID = notif.object as? UUID {
                viewModel.snapshots.removeAll(where: { $0.id == deletedID })
                serviceStateStore.removeService(deletedID)
                if viewModel.selectedServiceID == deletedID {
                    viewModel.selectedServiceID = nil
                    viewModel.isInspectorPresented = false
                }
            } else {
                viewModel.loadWorkspace(workspaceID: workspaceID)
            }
        case .kumaGroupsUpdated:
            Task { await viewModel.refreshGroups(workspaceID: workspaceID) }
        case .kumaFocusSearch:
            isSearching = true
        case .kumaExportWorkspace:
            exportCurrentWorkspace()
        case .kumaImportWorkspace:
            promptImportFile()
        default:
            break
        }
    }
}
