import SwiftUI

public struct GroupDragDropModifier: ViewModifier {
    public let isGroupRow: Bool
    public let nodeID: UUID
    public let onReorder: ((UUID, UUID) -> Void)?
    @Binding public var isTargeted: Bool

    public init(
        isGroupRow: Bool,
        nodeID: UUID,
        onReorder: ((UUID, UUID) -> Void)?,
        isTargeted: Binding<Bool>
    ) {
        self.isGroupRow = isGroupRow
        self.nodeID = nodeID
        self.onReorder = onReorder
        self._isTargeted = isTargeted
    }

    public func body(content: Content) -> some View {
        if isGroupRow {
            content
                .draggable(nodeID.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first, let draggedID = UUID(uuidString: first) else { return false }
                    onReorder?(draggedID, nodeID)
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isTargeted = targeted
                    }
                }
        } else {
            content
        }
    }
}
