import SwiftUI

public enum KumaFormAddActionStyle {
    case textLink
    case bordered
}

public struct KumaFormAddActionButton: View {
    public let style: KumaFormAddActionStyle
    public let title: String
    public let helpWhenEnabled: String
    public let helpWhenDisabled: String
    public var accessibilityIdentifier: String?
    public let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered: Bool = false

    public init(
        style: KumaFormAddActionStyle,
        title: String,
        helpWhenEnabled: String,
        helpWhenDisabled: String = "Stop the service to edit.",
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.title = title
        self.helpWhenEnabled = helpWhenEnabled
        self.helpWhenDisabled = helpWhenDisabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Group {
            switch style {
            case .textLink:
                Button(action: action) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering in
                    if isEnabled { isHovered = hovering }
                }

            case .bordered:
                Button(action: action) {
                    Label(title, systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
            }
        }
        .help(isEnabled ? helpWhenEnabled : helpWhenDisabled)
        .optionalAccessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
