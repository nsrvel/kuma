import SwiftUI

/// Compact inspector segment control (icon or icon + title) matching `KumaSourceField` mode tabs.
public struct KumaInspectorSegmentButton: View {
    public let systemImage: String
    public var title: String?
    public let isSelected: Bool
    public var isDisabled: Bool
    public let accessibilityLabel: String
    public var help: String?
    public let action: () -> Void

    @State private var isHovered = false

    public init(
        systemImage: String,
        title: String? = nil,
        isSelected: Bool,
        isDisabled: Bool = false,
        accessibilityLabel: String,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.accessibilityLabel = accessibilityLabel
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    KumaInspectorListRowSelectionChrome(
                        isSelected: isSelected,
                        isHovered: isHovered,
                        style: .segmentControl
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(help ?? "")
    }

    private var labelForeground: Color {
        if isDisabled { return Color.secondary.opacity(0.4) }
        return isSelected ? Color.primary : Color.secondary
    }

    @ViewBuilder
    private var label: some View {
        if let title, !title.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(labelForeground)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(labelForeground)
                    .lineLimit(1)
            }
            .opacity(isDisabled ? 0.45 : 1)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.4) : (isSelected ? Color.primary : Color.secondary))
        }
    }
}
