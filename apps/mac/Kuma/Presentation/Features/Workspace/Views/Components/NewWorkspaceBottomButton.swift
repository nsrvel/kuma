import SwiftUI

// MARK: - NewWorkspaceBottomButton

public struct NewWorkspaceBottomButton: View {
    public let action: () -> Void
    @State private var isHovering = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    private var rowBackground: some ShapeStyle {
        if isHovering {
            return AnyShapeStyle(Color.secondary.opacity(KumaTheme.Sidebar.hoverBgOpacity))
        }
        return AnyShapeStyle(Color.clear)
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "plus")
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18, height: 18)
                    .padding(.trailing, 8)

                Text("New Workspace")
                    .font(.system(size: 13, weight: .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .frame(minHeight: KumaTheme.Sidebar.rowMinHeight)
            .contentShape(Rectangle())
            .padding(.vertical, KumaTheme.Sidebar.rowVerticalPadding)
            .padding(.horizontal, KumaTheme.Sidebar.rowHorizontalPadding)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: KumaTheme.Sidebar.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    NewWorkspaceBottomButton(action: {})
        .frame(width: 250)
        .padding()
}
