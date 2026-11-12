import SwiftUI

public struct ProviderItemRowView: View {
    let provider: Provider
    let isSelected: Bool
    let isLocked: Bool
    let canDelete: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    public init(
        provider: Provider,
        isSelected: Bool,
        isLocked: Bool,
        canDelete: Bool,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.provider = provider
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.canDelete = canDelete
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(provider.type.gradient)
                    .frame(width: 24, height: 24)

                ProviderBrandIcon(category: provider.type, tunnelType: provider.tunnelType, size: 12.5)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Text(provider.resolvedTarget)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                KumaStatusChip(
                    title: "Active",
                    tone: KumaStatus.runningIndicator,
                    showsLeadingIndicator: false,
                    showsCheckmarkLeading: true,
                    showsContainer: false
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background { KumaInspectorListRowSelectionChrome(isSelected: isSelected, isHovered: isHovered) }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if !isLocked {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                if canDelete {
                    Divider()
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .onTapGesture {
            if !isLocked {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    onSelect()
                }
            }
        }
    }
}
