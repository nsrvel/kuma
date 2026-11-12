import SwiftUI

/// Custom ButtonStyle providing Apple-grade tactile press state and crisp depth.
public struct KumaPrimaryButtonStyle: ButtonStyle {
    private let fill: Color
    private let maxWidth: CGFloat?
    private let minWidth: CGFloat?
    private let cornerRadius: CGFloat
    private let labelFont: Font
    private let verticalPadding: CGFloat
    private let horizontalPadding: CGFloat

    public init(
        fill: Color = Color.accentColor,
        maxWidth: CGFloat? = 220,
        minWidth: CGFloat? = nil,
        cornerRadius: CGFloat = KumaRadius.md,
        labelFont: Font = KumaFont.heading,
        verticalPadding: CGFloat = 9,
        horizontalPadding: CGFloat = KumaSpacing.lg
    ) {
        self.fill = fill
        self.maxWidth = maxWidth
        self.minWidth = minWidth
        self.cornerRadius = cornerRadius
        self.labelFont = labelFont
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    /// Compact inspector Start/Stop — same fill treatment as wizard primary, smaller metrics.
    public static func inspectorToggle(isRunning: Bool) -> KumaPrimaryButtonStyle {
        KumaPrimaryButtonStyle(
            fill: isRunning ? KumaStatus.destructiveButtonFill : Color.accentColor,
            maxWidth: nil,
            minWidth: 56,
            cornerRadius: 7,
            labelFont: .system(size: 12.5, weight: .semibold),
            verticalPadding: 6.5,
            horizontalPadding: 16
        )
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(labelFont)
            .foregroundStyle(.white)
            .frame(minWidth: minWidth, maxWidth: maxWidth)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .brightness(configuration.isPressed ? -0.08 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.05 : 0.15), lineWidth: 0.5)
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.05 : 0.12),
                radius: configuration.isPressed ? 1 : 3,
                x: 0,
                y: configuration.isPressed ? 0.5 : 1.5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.18), value: fill)
            .contentShape(Rectangle())
    }
}

public struct KumaPrimaryButton: View {
    private let title: String
    private let icon: String?
    private let maxWidth: CGFloat?
    private let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        maxWidth: CGFloat? = 220,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.maxWidth = maxWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: KumaSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
            }
        }
        .buttonStyle(KumaPrimaryButtonStyle(maxWidth: maxWidth))
        .keyboardShortcut(.defaultAction)
    }
}

#Preview {
    VStack(spacing: KumaSpacing.lg) {
        KumaPrimaryButton("Continue", icon: "arrow.right") {}
        KumaPrimaryButton("Get Started") {}
    }
    .padding()
    .frame(width: 320)
}
