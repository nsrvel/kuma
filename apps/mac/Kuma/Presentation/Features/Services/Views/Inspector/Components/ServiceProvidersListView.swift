import SwiftUI

/// Provider rows list and Add Provider button view for ServiceProvidersSectionView.
public struct ServiceProvidersListView: View {
    public let providers: [Provider]
    public let activeProviderID: UUID?
    public let isLocked: Bool
    public let onSelectProvider: (UUID) -> Void
    public let onEdit: (Provider) -> Void
    public let onDelete: (Provider) -> Void
    public let onOpenAddForm: () -> Void

    public init(
        providers: [Provider],
        activeProviderID: UUID?,
        isLocked: Bool,
        onSelectProvider: @escaping (UUID) -> Void,
        onEdit: @escaping (Provider) -> Void,
        onDelete: @escaping (Provider) -> Void,
        onOpenAddForm: @escaping () -> Void
    ) {
        self.providers = providers
        self.activeProviderID = activeProviderID
        self.isLocked = isLocked
        self.onSelectProvider = onSelectProvider
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onOpenAddForm = onOpenAddForm
    }

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(providers) { provider in
                ProviderItemRowView(
                    provider: provider,
                    isSelected: activeProviderID == provider.id,
                    isLocked: isLocked,
                    canDelete: providers.count > 1,
                    onSelect: { onSelectProvider(provider.id) },
                    onEdit: { onEdit(provider) },
                    onDelete: { onDelete(provider) }
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
                title: "Add new provider",
                helpWhenEnabled: "Add new provider",
                helpWhenDisabled: "Stop service to add providers",
                accessibilityIdentifier: KumaUIID.inspectorAddProviderButton,
                action: onOpenAddForm
            )
            .disabled(isLocked)
            .offset(y: 24)
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 24)
    }
}
