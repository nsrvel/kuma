import SwiftUI

/// Per-card runtime observer — keeps `ServiceStateStore` out of the grid parent `ForEach`.
public struct ServiceCardRow: View {
    public let snapshot: ServiceCardSnapshot
    public let isSelected: Bool

    @State private var runtime: ServiceRuntimeState = .idle

    public init(snapshot: ServiceCardSnapshot, isSelected: Bool) {
        self.snapshot = snapshot
        self.isSelected = isSelected
    }

    public var body: some View {
        ServiceCardView(
            snapshot: snapshot,
            runtime: runtime,
            isSelected: isSelected
        )
        .equatable()
        .syncingServiceRuntime(serviceID: snapshot.id, runtime: $runtime)
    }
}

#Preview {
    ServiceCardRow(
        snapshot: ServiceCardSnapshot(id: UUID(), name: "Row Preview", providerCategory: .docker),
        isSelected: true
    )
    .environment(ServiceStateStore())
    .frame(width: KumaTheme.Deck.cardIdealWidth)
    .padding()
}
