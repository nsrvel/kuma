import SwiftUI

/// Modern Pill Capsule highlight for drag-and-drop targets in the Sidebar.
/// Replaces legacy 2px lines with a refined native macOS capsule glow & border.
public struct SidebarDropIndicator: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: KumaTheme.Sidebar.rowCornerRadius, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: KumaTheme.Sidebar.rowCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

#Preview {
    SidebarDropIndicator()
        .frame(width: 200, height: 28)
        .padding()
}
