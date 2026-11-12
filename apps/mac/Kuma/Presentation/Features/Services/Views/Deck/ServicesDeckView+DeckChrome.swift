import SwiftUI

extension ServicesDeckView {
    func applyDeckChrome<Content: View>(to content: Content) -> some View {
        content
            .sheet(item: $pendingImportBackup) { backup in
                let wsName = workspaceStore.workspaces.first(where: { $0.id == workspaceID })?.name ?? "Workspace"
                let existingNames = Set(viewModel.snapshots.map { $0.name.lowercased() })
                WorkspaceImportPreviewSheet(
                    backup: backup,
                    fileName: pendingImportFileName,
                    targetWorkspaceName: wsName,
                    targetWorkspaceID: workspaceID,
                    existingServiceNames: existingNames,
                    onConfirmImport: { selectedServiceIDs, resolvedNames in
                        executeImport(backup: backup, selectedServiceIDs: selectedServiceIDs, resolvedNames: resolvedNames)
                    }
                )
            }
            .alert("Workspace Data", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog(
                "Delete Service?",
                isPresented: Binding(
                    get: { viewModel.servicePendingDeletion != nil },
                    set: { if !$0 { viewModel.servicePendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.confirmDeletePendingService(workspaceID: workspaceID)
                }
                Button("Cancel", role: .cancel) {
                    viewModel.servicePendingDeletion = nil
                }
            } message: {
                Text("‘\(viewModel.servicePendingDeletion?.name ?? "Service")’ and its configurations will be permanently deleted.")
            }
            .inspector(isPresented: $viewModel.isInspectorPresented) {
                deckInspectorColumn
            }
            .background { deckHiddenKeyboardShortcuts }
    }

    @ViewBuilder
    private var deckInspectorColumn: some View {
        if let selectedID = viewModel.selectedServiceID {
            ServiceInspectorView(
                serviceID: selectedID,
                workspaceID: workspaceID
            )
            .inspectorColumnWidth(
                min: KumaTheme.Inspector.widthMin,
                ideal: KumaTheme.Inspector.widthIdeal,
                max: KumaTheme.Inspector.widthMax
            )
        } else {
            KumaEmptyStateView(
                iconName: "sidebar.right",
                title: "No Selection",
                description: "Select a service to view configuration details."
            )
            .inspectorColumnWidth(
                min: KumaTheme.Inspector.widthMin,
                ideal: KumaTheme.Inspector.widthIdeal,
                max: KumaTheme.Inspector.widthMax
            )
        }
    }

    private var deckHiddenKeyboardShortcuts: some View {
        Group {
            Button("") {
                if let id = viewModel.selectedServiceID {
                    viewModel.toggleService(id: id)
                }
            }
            .keyboardShortcut(KumaShortcuts.toggleService.key, modifiers: KumaShortcuts.toggleService.modifiers)

            Button("") {
                if let id = viewModel.selectedServiceID {
                    viewModel.restartService(id: id)
                }
            }
            .keyboardShortcut(KumaShortcuts.restartService.key, modifiers: KumaShortcuts.restartService.modifiers)

            Button("") {
                if viewModel.selectedServiceID != nil {
                    viewModel.selectService(nil)
                }
            }
            .keyboardShortcut(KumaShortcuts.dismiss.key, modifiers: KumaShortcuts.dismiss.modifiers)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
