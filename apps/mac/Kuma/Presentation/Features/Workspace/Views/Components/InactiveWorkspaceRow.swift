import SwiftUI

// MARK: - InactiveWorkspaceRow

public struct InactiveWorkspaceRow: View {
    public let workspace: Workspace
    public let shortcutIndex: Int?
    public let canDelete: Bool
    public let onSelect: () -> Void
    public let onEdit: () -> Void
    public let onDelete: () -> Void

    @State private var isHovered = false

    public init(
        workspace: Workspace,
        shortcutIndex: Int?,
        canDelete: Bool,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.shortcutIndex = shortcutIndex
        self.canDelete = canDelete
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 8) {
            WorkspaceAvatarView(workspace: workspace, size: KumaTheme.Sidebar.workspaceIconSize)

            Text(workspace.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer()

            // Static Shortcut Badge
            if let shortcutIndex {
                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .padding(.vertical, KumaTheme.Sidebar.rowVerticalPadding)
        .padding(.horizontal, KumaTheme.Sidebar.rowHorizontalPadding)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: KumaTheme.Sidebar.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(workspace.name)
        .accessibilityHint(shortcutIndex != nil ? "Switch to workspace, shortcut Command \(shortcutIndex!)" : "Switch to workspace")
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Switch to Workspace", systemImage: "arrow.right.circle")
            }

            Button {
                onEdit()
            } label: {
                Label("Workspace Settings", systemImage: "gearshape")
            }

            if canDelete {
                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    InactiveWorkspaceRow(
        workspace: Workspace(name: "Staging Backend"),
        shortcutIndex: 2,
        canDelete: true,
        onSelect: {},
        onEdit: {},
        onDelete: {}
    )
    .frame(width: 250)
    .padding()
}
