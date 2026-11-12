import SwiftUI

public struct SidebarChevron: View {
    public let isExpanded: Bool
    public var onToggle: (() -> Void)? = nil

    @State private var isHovering = false

    public init(isExpanded: Bool, onToggle: (() -> Void)? = nil) {
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        Button {
            onToggle?()
        } label: {
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse" : "Expand")
        .onHover { isHovering = $0 }
    }
}
