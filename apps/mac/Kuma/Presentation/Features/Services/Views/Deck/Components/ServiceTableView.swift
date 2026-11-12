import SwiftUI

/// Ultra-polished native macOS Table view for Services deck.
public struct ServiceTableView: View {
    public let snapshots: [ServiceCardSnapshot]
    public let selectedID: UUID?
    public let groupsProvider: () -> [ServiceGroup]
    public let handlers: ServiceTableActionHandlers

    @State private var selection: Set<UUID> = []

    public init(
        snapshots: [ServiceCardSnapshot],
        selectedID: UUID?,
        groupsProvider: @escaping () -> [ServiceGroup],
        handlers: ServiceTableActionHandlers
    ) {
        self.snapshots = snapshots
        self.selectedID = selectedID
        self.groupsProvider = groupsProvider
        self.handlers = handlers
    }

    public var body: some View {
        Table(snapshots, selection: $selection) {
            TableColumn("Name") { snapshot in
                ServiceTableNameCell(
                    snapshot: snapshot,
                    onSelect: handlers.onSelect
                )
            }
            .width(min: 160, ideal: 220)

            TableColumn("Provider") { snapshot in
                Text(snapshot.providerCategory.sidebarLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { handlers.onSelect(snapshot.id) }
            }
            .width(ideal: 90)

            TableColumn("Ports") { snapshot in
                ServiceTablePortsCell(snapshot: snapshot, onSelect: handlers.onSelect)
            }
            .width(ideal: 110)

            TableColumn("Status") { snapshot in
                ServiceTableStatusCell(
                    serviceID: snapshot.id,
                    isDisabled: snapshot.isDisabled,
                    onSelect: handlers.onSelect
                )
            }
            .width(ideal: 90)

            TableColumn("") { snapshot in
                ServiceTableActionsCell(
                    snapshot: snapshot,
                    groupsProvider: groupsProvider,
                    handlers: handlers
                )
            }
            .width(28)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .serviceTableContextMenu(
            snapshots: snapshots,
            groupsProvider: groupsProvider,
            handlers: handlers
        )
        .onChange(of: selection) { _, new in
            if let id = new.first, id != selectedID {
                handlers.onSelect(id)
            }
        }
        .onChange(of: selectedID) { _, id in
            if let id { selection = [id] } else { selection = [] }
        }
        .onAppear {
            if let selectedID { selection = [selectedID] }
        }
    }
}
