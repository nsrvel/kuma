import SwiftUI

// MARK: - KumaFormSection Style

public enum KumaFormSectionStyle {
    case standard
    case danger
}

// MARK: - KumaFormSection

public struct KumaFormSection<Content: View>: View {
    public let icon: String?
    public let title: String?
    public let style: KumaFormSectionStyle
    @ViewBuilder public let content: Content

    public init(
        icon: String? = nil,
        title: String? = nil,
        subtitle: String? = nil, // Kept optional for backward compatibility
        style: KumaFormSectionStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.style = style
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.sm) {
            if icon != nil || !(title?.isEmpty ?? true) {
                HStack(spacing: KumaSpacing.xs) {
                    if let icon {
                        Image(systemName: icon)
                            .font(KumaFont.caption)
                            .foregroundStyle(style == .danger ? Color.red : Color.secondary)
                    }
                    if let title {
                        Text(title.uppercased())
                            .font(KumaFont.captionBold)
                            .foregroundStyle(style == .danger ? Color.red : Color.secondary)
                    }
                }
                .padding(.horizontal, KumaSpacing.xs)
            }
            VStack(alignment: .leading, spacing: KumaSpacing.md) {
                content
            }
            .padding(KumaSpacing.lg)
            .background(KumaColors.surfaceBackground, in: RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        KumaFormSection(icon: "gearshape.fill", title: "General", subtitle: "Manage system preferences") {
            Text("Sample Content Area")
                .font(KumaFont.body)
        }

        KumaFormSection(icon: "exclamationmark.triangle.fill", title: "Danger Zone", style: .danger) {
            Text("Reset data and restart application")
                .font(KumaFont.body)
        }
    }
    .padding()
    .frame(width: 500)
}
