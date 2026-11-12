import SwiftUI

/// Card grid isolated from `ServicesDeckViewModel` — only snapshot/selection inputs invalidate rows.
public struct ServicesDeckCardGridView: View {
    public let snapshots: [ServiceCardSnapshot]
    public let selectedServiceID: UUID?
    public let filterVersion: Int

    public init(
        snapshots: [ServiceCardSnapshot],
        selectedServiceID: UUID?,
        filterVersion: Int
    ) {
        self.snapshots = snapshots
        self.selectedServiceID = selectedServiceID
        self.filterVersion = filterVersion
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: deckGridColumns, spacing: KumaTheme.Deck.gutter) {
                ForEach(snapshots) { snapshot in
                    ServiceCardRow(
                        snapshot: snapshot,
                        isSelected: selectedServiceID == snapshot.id
                    )
                }
            }
            .animation(nil, value: filterVersion)
            .padding(KumaTheme.Deck.gridPadding)
        }
    }

    private var deckGridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: KumaTheme.Deck.cardMinWidth,
                    maximum: KumaTheme.Deck.cardMaxWidth
                ),
                spacing: KumaTheme.Deck.gutter
            ),
        ]
    }
}

#Preview {
    ServicesDeckCardGridView(
        snapshots: [
            ServiceCardSnapshot(id: UUID(), name: "Preview", providerCategory: .docker),
        ],
        selectedServiceID: nil,
        filterVersion: 0
    )
    .environment(ServiceStateStore())
}
