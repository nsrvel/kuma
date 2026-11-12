import SwiftUI

public struct SidebarFooterButton: View {
    public let icon: String
    public let tooltip: String
    public let isSelected: Bool
    public let action: () -> Void

    @State private var isHovering = false

    public init(
        icon: String,
        tooltip: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tooltip = tooltip
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(foregroundColor)
                .frame(width: 24, height: 24)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        if isSelected || isHovering {
            return Color.primary
        }
        return Color.secondary
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.secondary.opacity(KumaTheme.Sidebar.selectedBgOpacity * 1.5)
        }
        if isHovering {
            return Color.secondary.opacity(0.12)
        }
        return Color.clear
    }
}
