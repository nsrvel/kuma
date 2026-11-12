import SwiftUI

public struct SidebarActionButton: View {
    public let icon: String
    public let tooltip: String
    public let action: () -> Void

    @State private var isHovering = false

    public init(icon: String, tooltip: String, action: @escaping () -> Void) {
        self.icon = icon
        self.tooltip = tooltip
        self.action = action
    }

    public init(action: SidebarAction) {
        self.icon = action.icon
        self.tooltip = action.tooltip
        self.action = action.handler
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovering ? Color.primary : Color.secondary)
                .frame(width: KumaTheme.Sidebar.actionButtonSize, height: KumaTheme.Sidebar.actionButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityAddTraits(.isButton)
        .transaction { $0.animation = nil }
        .onHover { isHovering = $0 }
    }
}
