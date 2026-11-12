import SwiftUI

/// Reusable table column cell renderers for ServiceTableView.
public struct ServiceTableNameCell: View {
    public let snapshot: ServiceCardSnapshot
    public let onSelect: (UUID) -> Void

    public init(snapshot: ServiceCardSnapshot, onSelect: @escaping (UUID) -> Void) {
        self.snapshot = snapshot
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(
                        snapshot.isDisabled
                        ? LinearGradient(colors: [Color.secondary.opacity(0.18), Color.secondary.opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : snapshot.providerCategory.gradient
                    )
                    .frame(width: 24, height: 24)
                    .shadow(color: Color.black.opacity(snapshot.isDisabled ? 0.0 : 0.12), radius: 1, y: 0.5)

                ProviderBrandIcon(category: snapshot.providerCategory, size: 12.5)
                    .foregroundStyle(snapshot.isDisabled ? Color.secondary : Color.white)
            }

            HStack(spacing: 5) {
                Text(snapshot.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(snapshot.isDisabled ? .secondary : .primary)
                    .lineLimit(1)

                if snapshot.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.yellow)
                }

                if snapshot.isDisabled {
                    Text("disabled")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(snapshot.id) }
    }
}

/// Live status cell — reads `ServiceStateStore` per row.
public struct ServiceTableStatusCell: View {
    public let serviceID: UUID
    public let isDisabled: Bool
    public let onSelect: (UUID) -> Void

    @State private var runtime: ServiceRuntimeState = .idle

    public var body: some View {
        ServiceStatusObserver(
            state: runtime,
            isDisabled: isDisabled
        )
        .syncingServiceRuntime(serviceID: serviceID, runtime: $runtime)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(serviceID) }
    }
}

/// Actions menu button cell for ServiceTableView.
public struct ServiceTableActionsCell: View {
    public let snapshot: ServiceCardSnapshot
    public let groupsProvider: () -> [ServiceGroup]
    public let handlers: ServiceTableActionHandlers

    @State private var runtime: ServiceRuntimeState = .idle

    public init(
        snapshot: ServiceCardSnapshot,
        groupsProvider: @escaping () -> [ServiceGroup],
        handlers: ServiceTableActionHandlers
    ) {
        self.snapshot = snapshot
        self.groupsProvider = groupsProvider
        self.handlers = handlers
    }

    public var body: some View {
        Menu {
            ServiceActionContextMenu(
                snapshot: snapshot,
                runtime: runtime,
                groupsProvider: groupsProvider,
                selectedGroupIDsProvider: { handlers.groupIDsForService(snapshot.id) },
                onToggle: { handlers.onToggle(snapshot.id) },
                onRestart: { handlers.onRestart(snapshot.id) },
                onSwitchProvider: { provID in handlers.onSwitchProvider(snapshot.id, provID) },
                onToggleStar: { handlers.onToggleStar(snapshot.id) },
                onToggleDisabled: { handlers.onToggleDisabled(snapshot.id) },
                onToggleGroup: { groupID in handlers.onToggleGroup(snapshot.id, groupID) },
                onDuplicate: { handlers.onDuplicate(snapshot.id) },
                onCopyConfig: { handlers.onCopyConfig(snapshot.id) },
                onDelete: { handlers.onDelete(snapshot.id) },
                onSelect: { handlers.onSelect(snapshot.id) }
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .accessibilityLabel("Service actions")
        .help("Service actions")
        .syncingServiceRuntime(serviceID: snapshot.id, runtime: $runtime)
    }
}

/// Ports column cell for ServiceTableView.
public struct ServiceTablePortsCell: View {
    public let snapshot: ServiceCardSnapshot
    public let onSelect: (UUID) -> Void

    public var body: some View {
        Group {
            if snapshot.portDisplays.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                PortChipsView(ports: snapshot.portDisplays)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(snapshot.id) }
    }
}
