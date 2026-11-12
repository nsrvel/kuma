import SwiftUI

public struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel
    @Bindable var workspaceStore: WorkspaceStore

    public init(viewModel: SidebarViewModel, workspaceStore: WorkspaceStore) {
        self.viewModel = viewModel
        self.workspaceStore = workspaceStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Navigation List (Pure Apple HIG Native Inset Layout - Tight Margins)
            List {
                // 1. Workspace header row + divider
                VStack(spacing: 0) {
                    SidebarWorkspaceRow(store: workspaceStore)

                    KumaDivider(opacity: 0.08, verticalPadding: 6, horizontalPadding: 8)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // 2. Main Navigation Items
                ForEach(viewModel.flattenedRows) { item in
                    VStack(spacing: 0) {
                        cellView(for: item)

                        if item.hasDividerAfter {
                            KumaDivider(opacity: 0.08, verticalPadding: 6, horizontalPadding: 8)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .padding(.horizontal, -4)
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    viewModel.handleMove(direction)
                }
            }

            // 3. Extracted Modular Sidebar Sticky Footer
            SidebarFooterView(viewModel: viewModel)
        }
        .navigationSplitViewColumnWidth(
            min: KumaTheme.Sidebar.widthMin,
            ideal: KumaTheme.Sidebar.widthIdeal,
            max: KumaTheme.Sidebar.widthMax
        )
        .task(id: workspaceStore.activeWorkspace?.id) {
            if let wsID = workspaceStore.activeWorkspace?.id {
                await viewModel.loadGroups(workspaceID: wsID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kumaGroupsUpdated)) { _ in
            guard let wsID = workspaceStore.activeWorkspace?.id else { return }
            Task { await viewModel.loadGroups(workspaceID: wsID) }
        }
    }

    @ViewBuilder
    private func cellView(for item: SidebarViewModel.FlattenedRow) -> some View {
        switch item.entry {
        case .item(let node):
            if item.isPlaceholder {
                SidebarEmptyPlaceholderRow(title: node.title, indentLevel: item.indentLevel)
            } else {
                SidebarRowView(
                    node: node,
                    isSelected: viewModel.selectedID == node.id,
                    isExpanded: viewModel.isExpanded(node.id),
                    isEditing: viewModel.editingGroupID == node.id,
                    indentLevel: item.indentLevel,
                    onSelect: {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            viewModel.selectedID = node.id
                        }
                    },
                    onToggleExpand: {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                            viewModel.toggleExpanded(node.id)
                        }
                    },
                    onAddAction: node.id == .stable("groups") ? {
                        if let wsID = workspaceStore.activeWorkspace?.id {
                            viewModel.addGroup(workspaceID: wsID)
                        }
                    } : nil,
                    onCommitRename: { newName in
                        viewModel.renameGroup(id: node.id, newName: newName)
                    },
                    onStartRename: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                            viewModel.editingGroupID = node.id
                        }
                    },
                    onDelete: {
                        AlertService.shared.confirmDelete(
                            title: "Delete Group?",
                            message: "Services in “\(node.title)” will remain in your workspace.",
                            confirmTitle: "Delete"
                        ) {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                viewModel.deleteGroup(id: node.id)
                            }
                        }
                    },
                    onMoveUp: viewModel.canMoveGroupUp(id: node.id) ? {
                        viewModel.moveGroupUp(id: node.id)
                    } : nil,
                    onMoveDown: viewModel.canMoveGroupDown(id: node.id) ? {
                        viewModel.moveGroupDown(id: node.id)
                    } : nil,
                    onReorderGroup: { draggedID, targetID in
                        viewModel.reorderGroup(draggedID: draggedID, targetID: targetID)
                    }
                )
            }

        case .divider:
            EmptyView()
        }
    }
}

#Preview {
    SidebarView(
        viewModel: SidebarViewModel.makeDefault(),
        workspaceStore: WorkspaceStore()
    )
    .frame(width: 220, height: 600)
}
