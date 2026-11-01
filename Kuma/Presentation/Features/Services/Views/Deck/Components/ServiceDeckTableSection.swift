import SwiftUI

/// Table list without holding `ServicesDeckViewModel`.
struct ServiceDeckTableSection: View {
    let snapshots: [ServiceCardSnapshot]
    let selectedServiceID: UUID?
    let actions: ServiceDeckActions

    var body: some View {
        ServiceTableView(
            snapshots: snapshots,
            selectedID: selectedServiceID,
            groupsProvider: actions.groups,
            handlers: actions.tableHandlers
        )
    }
}
