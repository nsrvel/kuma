import SwiftUI

// MARK: - KumaBannerStyle

public enum KumaBannerStyle {
    case warning
    case error
    case info

    public var icon: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    public var primaryColor: Color {
        switch self {
        case .warning: return .orange
        case .error: return .red
        case .info: return .accentColor
        }
    }
}

// MARK: - KumaNoticeBanner

/// Reusable notice & warning banner with icon, title, message, and optional action button.
public struct KumaNoticeBanner: View {
    public let style: KumaBannerStyle
    public let title: String
    public let message: String
    public var actionIcon: String?
    public var actionHint: String?
    public var onAction: (() -> Void)?

    public init(
        style: KumaBannerStyle = .warning,
        title: String,
        message: String,
        actionIcon: String? = nil,
        actionHint: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.style = style
        self.title = title
        self.message = message
        self.actionIcon = actionIcon
        self.actionHint = actionHint
        self.onAction = onAction
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.icon)
                .font(.system(size: 12))
                .foregroundStyle(style.primaryColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.85))

                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let onAction {
                Button(action: onAction) {
                    Image(systemName: actionIcon ?? "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(style.primaryColor)
                }
                .buttonStyle(.plain)
                .help(actionHint ?? "Retry")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(style.primaryColor.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style.primaryColor.opacity(0.2), lineWidth: 0.5)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        KumaNoticeBanner(
            style: .warning,
            title: "Offline Mode / Unreachable Cluster",
            message: "Unable to connect automatically. Fell back to manual text input.",
            actionIcon: "arrow.clockwise",
            actionHint: "Retry connection test",
            onAction: {}
        )

        KumaNoticeBanner(
            style: .error,
            title: "Invalid Port Mapping",
            message: "Port must be a valid number between 1 and 65535."
        )
    }
    .padding()
    .frame(width: 480)
    .background(KumaColors.canvasBackground)
}
