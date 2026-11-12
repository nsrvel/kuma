import SwiftUI

// MARK: - WorkspaceAvatarRemoveBadge

public struct WorkspaceAvatarRemoveBadge: View {
    public let onRemove: () -> Void
    @State private var isHovering = false

    public init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    public var body: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isHovering ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isHovering ? Color.red : Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    Circle()
                        .stroke(isHovering ? Color.red : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                .scaleEffect(isHovering ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove workspace photo")
        .help("Remove photo")
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
    }
}
