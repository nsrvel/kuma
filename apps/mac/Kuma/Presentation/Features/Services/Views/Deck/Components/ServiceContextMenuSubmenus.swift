import SwiftUI

/// Leading checkmark column so macOS context menus show membership like native toggles.
private struct ContextMenuCheckRow: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .opacity(isChecked ? 1 : 0)
                .frame(width: 12, alignment: .leading)
            Text(title)
        }
    }
}

public struct ServiceProviderSwitchSubmenu: View {
    public let snapshot: ServiceCardSnapshot
    public let onSwitchProvider: (UUID) -> Void

    public var body: some View {
        Menu {
            if !snapshot.providerOptions.isEmpty {
                ForEach(snapshot.providerOptions) { option in
                    Button {
                        onSwitchProvider(option.id)
                    } label: {
                        ContextMenuCheckRow(title: option.label, isChecked: option.isActive)
                    }
                }
            } else {
                Button {} label: {
                    ContextMenuCheckRow(title: snapshot.providerCategory.sidebarLabel, isChecked: true)
                }
                .disabled(true)
            }
        } label: {
            Label("Switch Provider", systemImage: "arrow.triangle.2.circlepath")
        }
    }
}

public struct ServiceGroupsSubmenu: View {
    public let groups: [ServiceGroup]
    public let selectedGroupIDsProvider: () -> Set<UUID>
    public let onToggleGroup: (UUID) -> Void

    public var body: some View {
        if !groups.isEmpty {
            let selectedGroupIDs = selectedGroupIDsProvider()
            Menu {
                ForEach(groups) { group in
                    Toggle(isOn: Binding(
                        get: { selectedGroupIDsProvider().contains(group.id) },
                        set: { _ in onToggleGroup(group.id) }
                    )) {
                        Text(group.name)
                    }
                }
            } label: {
                Label("Groups", systemImage: "folder")
            }
            .id(selectedGroupIDs.sorted { $0.uuidString < $1.uuidString })
        }
    }
}
