import SwiftUI

// MARK: - Appearance Card

public struct AppearanceCard: View {
    public let mode: KumaAppearance
    public let isSelected: Bool
    public let namespace: Namespace.ID
    public let onSelect: () -> Void

    @State private var isHovered = false

    public init(
        mode: KumaAppearance,
        isSelected: Bool,
        namespace: Namespace.ID,
        onSelect: @escaping () -> Void
    ) {
        self.mode = mode
        self.isSelected = isSelected
        self.namespace = namespace
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(spacing: KumaSpacing.sm) {
                themePreview

                HStack(spacing: KumaSpacing.xs) {
                    Image(systemName: iconForMode(mode))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    Text(mode.title)
                        .font(KumaFont.caption)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .padding(.bottom, KumaSpacing.xs)
            }
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                            .matchedGeometryEffect(id: "themeCardSelectionBg", in: namespace)
                    }
                }
            )
            .overlay(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: KumaRadius.md, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                            .matchedGeometryEffect(id: "themeCardSelectionBorder", in: namespace)
                    }
                }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(ThemeCardButtonStyle())
        .onHover { isHovered = $0 }
    }

    private func iconForMode(_ mode: KumaAppearance) -> String {
        switch mode {
        case .system: return "circle.righthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    // MARK: - V3 Iconic Low-Poly Mini-Window (Authentic True Split for System)

    private var themePreview: some View {
        ZStack {
            if mode == .system {
                // True 50:50 Split: Left Half 100% Light, Right Half 100% Dark
                ZStack {
                    // Dark Base (Right Side)
                    windowBody(isDark: true)

                    // Light Base (Left Side) with exact 50% split mask
                    windowBody(isDark: false)
                        .mask(
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * 0.5)
                            }
                        )

                    // Subtle hairline center divider
                    GeometryReader { geo in
                        Path { path in
                            path.move(to: CGPoint(x: geo.size.width * 0.5, y: 0))
                            path.addLine(to: CGPoint(x: geo.size.width * 0.5, y: geo.size.height))
                        }
                        .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                    }
                }
            } else {
                windowBody(isDark: mode == .dark)
            }
        }
        .frame(height: 72)
        .clipShape(RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
        .padding(.horizontal, KumaSpacing.sm)
        .padding(.top, KumaSpacing.sm)
    }

    @ViewBuilder
    private func windowBody(isDark: Bool) -> some View {
        ZStack {
            Rectangle().fill(isDark ? Color(white: 0.15) : Color.white)

            VStack(spacing: 0) {
                // Titlebar with Traffic Lights (Exact V3 5pt)
                HStack(spacing: 3) {
                    Circle().fill(Color.red.opacity(0.8)).frame(width: 5, height: 5)
                    Circle().fill(Color.orange.opacity(0.8)).frame(width: 5, height: 5)
                    Circle().fill(Color.green.opacity(0.8)).frame(width: 5, height: 5)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isDark ? Color(white: 0.22) : Color(white: 0.92))

                // Body: Sidebar + Content Canvas
                HStack(spacing: 0) {
                    // Sidebar
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color(white: 0.35) : Color(white: 0.75))
                            .frame(width: 24, height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color(white: 0.55) : Color(white: 0.50))
                            .frame(width: 28, height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color(white: 0.35) : Color(white: 0.75))
                            .frame(width: 20, height: 4)
                    }
                    .padding(5)
                    .frame(width: 40)
                    .background(isDark ? Color(white: 0.18) : Color(white: 0.95))

                    // Content Stage
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color(white: 0.3) : Color(white: 0.8))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isDark ? Color(white: 0.3) : Color(white: 0.8))
                            .frame(width: 40, height: 4)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(isDark ? Color(white: 0.13) : Color.white)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(KumaSpacing.md)
        }
    }
}

// MARK: - Custom Card ButtonStyle (No Opacity Fade on Hold)

private struct ThemeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
