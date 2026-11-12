import SwiftUI

public struct WorkspaceSwitcherPopover: View {
    @Bindable var store: WorkspaceStore
    @Binding var isPresented: Bool

    @State private var isHoveringActiveRow = false
    @State private var isHoveringActiveSettings = false

    public init(store: WorkspaceStore, isPresented: Binding<Bool>) {
        self.store = store
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let activeWS = store.activeWorkspace {
                activeWorkspaceRow(activeWS)
            }

            let inactiveWS = store.workspaces.filter { $0.id != store.selectedWorkspaceId }
            if !inactiveWS.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 2) {
                        ForEach(Array(inactiveWS.enumerated()), id: \.element.id) { index, ws in
                            let fullIndex = (store.workspaces.firstIndex(where: { $0.id == ws.id }) ?? index) + 1
                            InactiveWorkspaceRow(
                                workspace: ws,
                                shortcutIndex: fullIndex <= 9 ? fullIndex : nil,
                                canDelete: store.workspaces.count > 1,
                                onSelect: {
                                    KumaHapticManager.shared.levelChange()
                                    store.selectWorkspace(ws)
                                    isPresented = false
                                },
                                onEdit: {
                                    isPresented = false
                                    store.workspaceToEdit = ws
                                },
                                onDelete: {
                                    isPresented = false
                                    AlertService.shared.confirmDelete(
                                        title: "Delete Workspace?",
                                        message: "All services and configurations in “\(ws.name)” will be permanently deleted. This action cannot be undone.",
                                        onConfirm: {
                                            store.deleteWorkspace(ws)
                                        }
                                    )
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxHeight: 220)
                .padding(.top, 2)
            }

            KumaDivider(opacity: 0.06, verticalPadding: 6, horizontalPadding: 10)

            NewWorkspaceBottomButton {
                isPresented = false
                store.showCreateSheet = true
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: KumaTheme.Workspace.popoverWidth)
    }

    private func activeWorkspaceRow(_ activeWS: Workspace) -> some View {
        HStack(spacing: 10) {
            WorkspaceAvatarView(workspace: activeWS, size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(activeWS.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Text("Active Workspace")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }

            Spacer()

            Button {
                isPresented = false
                store.workspaceToEdit = activeWS
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(isHoveringActiveSettings ? 1.0 : 0.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringActiveSettings = $0 }
            .help("Workspace Settings")
        }
        .padding(8)
        .background(Color.primary.opacity(isHoveringActiveRow ? 0.05 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isHoveringActiveRow ? 0.10 : 0.06), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHoveringActiveRow = hovering
            }
        }
        .contextMenu {
            Button {
                isPresented = false
                store.workspaceToEdit = activeWS
            } label: {
                Label("Workspace Settings", systemImage: "gearshape")
            }

            if store.workspaces.count > 1 {
                Divider()
                Button(role: .destructive) {
                    isPresented = false
                    AlertService.shared.confirmDelete(
                        title: "Delete Workspace?",
                        message: "All services and configurations in “\(activeWS.name)” will be permanently deleted. This action cannot be undone.",
                        onConfirm: {
                            store.deleteWorkspace(activeWS)
                        }
                    )
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

#Preview {
    WorkspaceSwitcherPopover(
        store: WorkspaceStore(initialWorkspaces: [
            Workspace(name: "Default Workspace"),
            Workspace(name: "Staging Backend"),
            Workspace(name: "Production Cluster")
        ]),
        isPresented: .constant(true)
    )
}
