import SwiftUI

/// Isolated content body switcher for ServicesDeckView (Empty State, Cards Grid, or Table List).
public struct ServicesDeckContentBodyView: View {
    public let hasInitialLoaded: Bool
    public let allSnapshotsEmpty: Bool
    public let filteredSnapshots: [ServiceCardSnapshot]
    public let filterVersion: Int
    public let selectedServiceID: UUID?
    public let viewMode: DeckViewMode
    public let isStarredOnly: Bool
    public let deckActions: ServiceDeckActions

    public init(
        hasInitialLoaded: Bool,
        allSnapshotsEmpty: Bool,
        filteredSnapshots: [ServiceCardSnapshot],
        filterVersion: Int,
        selectedServiceID: UUID?,
        viewMode: DeckViewMode,
        isStarredOnly: Bool,
        deckActions: ServiceDeckActions
    ) {
        self.hasInitialLoaded = hasInitialLoaded
        self.allSnapshotsEmpty = allSnapshotsEmpty
        self.filteredSnapshots = filteredSnapshots
        self.filterVersion = filterVersion
        self.selectedServiceID = selectedServiceID
        self.viewMode = viewMode
        self.isStarredOnly = isStarredOnly
        self.deckActions = deckActions
    }

    public var body: some View {
        if !hasInitialLoaded {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredSnapshots.isEmpty {
            emptyStateView
        } else if viewMode == .card {
            ServicesDeckCardGridView(
                snapshots: filteredSnapshots,
                selectedServiceID: selectedServiceID,
                filterVersion: filterVersion
            )
        } else {
            ServiceDeckTableSection(
                snapshots: filteredSnapshots,
                selectedServiceID: selectedServiceID,
                actions: deckActions
            )
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if isStarredOnly {
            KumaEmptyStateView(
                iconName: "star.slash",
                title: "No Starred Services",
                description: "Star your most frequently used services from the context menu to access them quickly from here."
            )
        } else if allSnapshotsEmpty {
            KumaEmptyStateView(
                iconName: "square.stack.3d.up.slash",
                title: "No Services Yet",
                description: "Create a service to start port-forwarding, container, or shell runs.",
                actionButtonTitle: "Create Service",
                action: {
                    NotificationCenter.default.post(name: .kumaCreateServiceRequested, object: nil)
                }
            )
        } else {
            KumaEmptyStateView(
                iconName: "magnifyingglass",
                title: "No Services Found",
                description: "Try refining your search text or active filter options."
            )
        }
    }
}

#Preview {
    let workspaceID = UUID()
    let snapshots = [
        ServiceCardSnapshot(id: UUID(), name: "Preview", providerCategory: .shell),
    ]
    let actions = ServiceDeckActions(
        workspaceID: workspaceID,
        groups: { [] },
        groupIDsForService: { _ in [] },
        onSelect: { _ in },
        onToggle: { _ in },
        onRestart: { _ in },
        onSwitchProvider: { _, _ in },
        onToggleStar: { _ in },
        onToggleDisabled: { _ in },
        onToggleGroup: { _, _ in },
        onDuplicate: { _ in },
        onCopyConfig: { _ in },
        onDelete: { _ in }
    )
    return ServicesDeckContentBodyView(
        hasInitialLoaded: true,
        allSnapshotsEmpty: false,
        filteredSnapshots: snapshots,
        filterVersion: 0,
        selectedServiceID: nil,
        viewMode: .card,
        isStarredOnly: false,
        deckActions: actions
    )
    .environment(\.serviceDeckActions, actions)
    .environment(ServiceStateStore())
    .frame(width: 600, height: 400)
}
