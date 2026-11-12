import SwiftUI

public struct KubeConfigConnectionView: View {
    @Bindable var viewModel: KubeConfigViewModel

    let isLocked: Bool
    let contextToTest: String
    let onConfigChanged: () -> Void

    public init(
        viewModel: KubeConfigViewModel,
        isLocked: Bool = false,
        contextToTest: String = "",
        onConfigChanged: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.isLocked = isLocked
        self.contextToTest = contextToTest
        self.onConfigChanged = onConfigChanged
    }

    public var body: some View {
        KumaFormSection(icon: "server.rack", title: "Kube Config") {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.availableKubeConfigs.isEmpty && !viewModel.showInlineNewConfigForm {
                    emptyStateView
                } else if !viewModel.showInlineNewConfigForm {
                    configListView
                } else {
                    KubeConfigInlineEditorView(
                        viewModel: viewModel,
                        onDismiss: { viewModel.showInlineNewConfigForm = false },
                        onSaveSuccess: onConfigChanged
                    )
                    .disabled(isLocked)
                }
            }
            .confirmationDialog("Delete Kubeconfig?", isPresented: $viewModel.showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteConfig()
                        onConfigChanged()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteConfirmationMessage)
            }
            .onChange(of: isLocked) { _, locked in
                if locked && viewModel.showInlineNewConfigForm {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.showInlineNewConfigForm = false
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("No kubeconfigs registered.")
                .font(.caption)
                .foregroundStyle(.secondary)

            KumaFormAddActionButton(
                style: .bordered,
                title: "Add Kubeconfig",
                helpWhenEnabled: "Add Kubeconfig",
                helpWhenDisabled: "Stop service to add kubeconfigs",
                action: openNewKubeConfigForm
            )
            .disabled(isLocked)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    private var configListView: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.availableKubeConfigs) { config in
                KubeConfigItemRowView(
                    config: config,
                    isSelected: viewModel.selectedKubeConfigID == config.id,
                    isLocked: isLocked,
                    isLoadingNamespaces: viewModel.isLoadingNamespaces,
                    hasConnectionError: viewModel.connectionError != nil,
                    contextToTest: contextToTest,
                    onSelect: {
                        viewModel.selectedKubeConfigID = config.id
                        onConfigChanged()
                    },
                    onEdit: {
                        viewModel.beginEditing(config: config)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.showInlineNewConfigForm = true
                        }
                    },
                    onDelete: {
                        viewModel.selectedKubeConfigID = config.id
                        viewModel.showDeleteConfirmation = true
                    },
                    onRefresh: {
                        viewModel.selectedKubeConfigID = config.id
                        onConfigChanged()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.01))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomLeading) {
            KumaFormAddActionButton(
                style: .textLink,
                title: "Add Kubeconfig",
                helpWhenEnabled: "Add Kubeconfig",
                helpWhenDisabled: "Stop service to add kubeconfigs",
                action: openNewKubeConfigForm
            )
            .disabled(isLocked)
            .offset(y: 24)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 24)
    }

    private var deleteConfirmationMessage: String {
        let name = viewModel.availableKubeConfigs
            .first(where: { $0.id == viewModel.selectedKubeConfigID })?
            .name
        if let name, !name.isEmpty {
            return "‘\(name)’ will be removed from Kuma. The kubeconfig file on disk is not deleted."
        }
        return "This kubeconfig will be removed from Kuma. The file on disk is not deleted."
    }

    private func openNewKubeConfigForm() {
        viewModel.resetNewConfigForm()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.showInlineNewConfigForm = true
        }
    }
}
