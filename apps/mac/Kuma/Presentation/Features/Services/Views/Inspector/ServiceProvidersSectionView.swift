import SwiftUI

public struct ServiceProvidersSectionView: View {
    public let serviceID: UUID
    public let providers: [Provider]
    public let activeProviderID: UUID?
    public let isLocked: Bool
    public let onSelectProvider: (UUID) -> Void
    public let onAddProvider: (Provider) -> Void
    public let onUpdateProvider: (Provider) -> Void
    public let onDeleteProvider: (Provider) -> Void

    @State private var showInlineForm: Bool = false
    @State private var editingProviderID: UUID? = nil
    @State private var formType: ProviderCategory = .docker
    @State private var formLabel: String = ""
    @State private var showDeleteConfirmation: Bool = false
    @State private var providerToDelete: Provider? = nil

    public init(
        serviceID: UUID,
        providers: [Provider],
        activeProviderID: UUID?,
        isLocked: Bool = false,
        onSelectProvider: @escaping (UUID) -> Void,
        onAddProvider: @escaping (Provider) -> Void,
        onUpdateProvider: @escaping (Provider) -> Void = { _ in },
        onDeleteProvider: @escaping (Provider) -> Void
    ) {
        self.serviceID = serviceID
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.isLocked = isLocked
        self.onSelectProvider = onSelectProvider
        self.onAddProvider = onAddProvider
        self.onUpdateProvider = onUpdateProvider
        self.onDeleteProvider = onDeleteProvider
    }

    public var body: some View {
        KumaFormSection(
            icon: "square.stack.3d.down.right.fill",
            title: "Providers"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if providers.isEmpty && !showInlineForm {
                    emptyStateView
                } else if !showInlineForm {
                    providerListView
                } else {
                    ServiceProvidersInlineFormView(
                        isEditing: editingProviderID != nil,
                        formType: $formType,
                        formLabel: $formLabel,
                        onSave: { saveInlineForm() },
                        onCancel: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showInlineForm = false
                            }
                        }
                    )
                }
            }
            .confirmationDialog(
                "Delete Provider?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let provider = providerToDelete {
                        onDeleteProvider(provider)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("‘\(providerToDelete?.displayName ?? "This provider")’ and its settings will be deleted.")
            }
            .onChange(of: isLocked) { _, locked in
                if locked && showInlineForm {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showInlineForm = false
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("No providers configured.").font(.caption).foregroundStyle(.secondary)
            KumaFormAddActionButton(
                style: .bordered,
                title: "Add Provider",
                helpWhenEnabled: "Add new provider",
                helpWhenDisabled: "Stop service to add providers",
                action: openAddForm
            )
            .disabled(isLocked)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }

    private var providerListView: some View {
        ServiceProvidersListView(
            providers: providers,
            activeProviderID: activeProviderID,
            isLocked: isLocked,
            onSelectProvider: onSelectProvider,
            onEdit: { openEditForm($0) },
            onDelete: {
                providerToDelete = $0
                showDeleteConfirmation = true
            },
            onOpenAddForm: { openAddForm() }
        )
    }

    private func openAddForm() {
        formLabel = ""
        formType = .docker
        editingProviderID = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showInlineForm = true }
    }

    private func openEditForm(_ provider: Provider) {
        formLabel = provider.label ?? ""
        formType = provider.type
        editingProviderID = provider.id
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showInlineForm = true }
    }

    private func saveInlineForm() {
        let trimmed = formLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String? = trimmed.isEmpty ? nil : trimmed

        if let editingID = editingProviderID, let existing = providers.first(where: { $0.id == editingID }) {
            var updated = existing
            updated.label = label
            updated.type = formType
            updated.updatedAt = Date()
            onUpdateProvider(updated)
        } else {
            let newProv = Provider(id: UUID(), serviceID: serviceID, type: formType, label: label)
            onAddProvider(newProv)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showInlineForm = false }
    }
}
