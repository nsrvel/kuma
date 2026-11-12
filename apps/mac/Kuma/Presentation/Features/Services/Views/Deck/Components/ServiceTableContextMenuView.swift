import SwiftUI

extension View {
    @ViewBuilder
    public func serviceTableContextMenu(
        snapshots: [ServiceCardSnapshot],
        groupsProvider: @escaping () -> [ServiceGroup],
        handlers: ServiceTableActionHandlers
    ) -> some View {
        modifier(
            ServiceTableContextMenuModifier(
                snapshots: snapshots,
                groupsProvider: groupsProvider,
                handlers: handlers
            )
        )
    }
}

private struct ServiceTableContextMenuModifier: ViewModifier {
    let snapshots: [ServiceCardSnapshot]
    let groupsProvider: () -> [ServiceGroup]
    let handlers: ServiceTableActionHandlers

    @Environment(ServiceStateStore.self) private var serviceStateStore

    func body(content: Content) -> some View {
        content.contextMenu(forSelectionType: UUID.self) { selectedIDs in
            if let firstID = selectedIDs.first,
               let snapshot = snapshots.first(where: { $0.id == firstID }) {
                let runtime = serviceStateStore.runtime(for: snapshot.id)
                ServiceActionContextMenu(
                    snapshot: snapshot,
                    runtime: runtime,
                    groupsProvider: groupsProvider,
                    selectedGroupIDsProvider: { handlers.groupIDsForService(snapshot.id) },
                    onToggle: { handlers.onToggle(snapshot.id) },
                    onRestart: { handlers.onRestart(snapshot.id) },
                    onSwitchProvider: { provID in handlers.onSwitchProvider(snapshot.id, provID) },
                    onToggleStar: { handlers.onToggleStar(snapshot.id) },
                    onToggleDisabled: { handlers.onToggleDisabled(snapshot.id) },
                    onToggleGroup: { groupID in handlers.onToggleGroup(snapshot.id, groupID) },
                    onDuplicate: { handlers.onDuplicate(snapshot.id) },
                    onCopyConfig: { handlers.onCopyConfig(snapshot.id) },
                    onDelete: { handlers.onDelete(snapshot.id) },
                    onSelect: { handlers.onSelect(snapshot.id) }
                )
            }
        } primaryAction: { selectedIDs in
            if let firstID = selectedIDs.first {
                handlers.onSelect(firstID)
            }
        }
    }
}
