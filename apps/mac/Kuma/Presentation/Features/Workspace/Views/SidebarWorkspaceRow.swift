import SwiftUI

public struct SidebarWorkspaceRow: View {
    @Bindable var store: WorkspaceStore

    @State private var isHovering = false
    @State private var showSwitcher = false

    public init(store: WorkspaceStore) {
        self.store = store
    }

    private var rowBackground: some ShapeStyle {
        if isHovering || showSwitcher {
            return AnyShapeStyle(Color.secondary.opacity(KumaTheme.Sidebar.hoverBgOpacity))
        }
        return AnyShapeStyle(Color.clear)
    }

    public var body: some View {
        Button {
            showSwitcher = true
        } label: {
            HStack(spacing: 8) {
                // Workspace Avatar (V3 Metric: 22pt, CornerRadius: 5pt)
                if let active = store.activeWorkspace {
                    WorkspaceAvatarView(workspace: active, size: KumaTheme.Sidebar.workspaceIconSize)
                } else {
                    RoundedRectangle(cornerRadius: KumaTheme.Sidebar.workspaceCornerRadius, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: KumaTheme.Sidebar.workspaceIconSize, height: KumaTheme.Sidebar.workspaceIconSize)
                }

                // Workspace Name (V3 Typography: 13pt Semibold)
                Text(store.activeWorkspace?.name ?? "Workspace")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Subdued Chevron Indicator (Reveals on hover/active)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .opacity((isHovering || showSwitcher) ? 0.8 : 0.0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, KumaTheme.Sidebar.rowVerticalPadding)
        .padding(.horizontal, KumaTheme.Sidebar.rowHorizontalPadding)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: KumaTheme.Sidebar.rowCornerRadius, style: .continuous))
        .foregroundStyle(Color.primary)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .popover(isPresented: $showSwitcher, arrowEdge: .trailing) {
            WorkspaceSwitcherPopover(store: store, isPresented: $showSwitcher)
        }
        .accessibilityLabel(store.activeWorkspace?.name ?? "Workspace")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    SidebarWorkspaceRow(store: WorkspaceStore())
        .frame(width: 220)
        .padding()
}
