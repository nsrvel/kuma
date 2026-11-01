import SwiftUI

/// Context menu content for deck cards — built only when the menu opens.
struct ServiceCardContextMenu: View {
    let snapshot: ServiceCardSnapshot
    let runtime: ServiceRuntimeState

    @Environment(\.serviceDeckActions) private var deckActions

    var body: some View {
        if let deckActions {
            ServiceActionContextMenu(
                snapshot: snapshot,
                runtime: runtime,
                groupsProvider: deckActions.groups,
                selectedGroupIDsProvider: { deckActions.groupIDsForService(snapshot.id) },
                onToggle: { deckActions.onToggle(snapshot.id) },
                onRestart: { deckActions.onRestart(snapshot.id) },
                onSwitchProvider: { deckActions.onSwitchProvider(snapshot.id, $0) },
                onToggleStar: { deckActions.onToggleStar(snapshot.id) },
                onToggleDisabled: { deckActions.onToggleDisabled(snapshot.id) },
                onToggleGroup: { deckActions.onToggleGroup(snapshot.id, $0) },
                onDuplicate: { deckActions.onDuplicate(snapshot.id) },
                onCopyConfig: { deckActions.onCopyConfig(snapshot.id) },
                onDelete: { deckActions.onDelete(snapshot.id) },
                onSelect: { deckActions.onSelect(snapshot.id) }
            )
        }
    }
}
