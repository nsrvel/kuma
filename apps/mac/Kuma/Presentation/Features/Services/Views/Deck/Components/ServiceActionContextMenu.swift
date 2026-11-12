import SwiftUI
import AppKit

public struct ServiceActionContextMenu: View {
    public let snapshot: ServiceCardSnapshot
    public let runtime: ServiceRuntimeState
    public var groupsProvider: () -> [ServiceGroup]
    public var selectedGroupIDsProvider: () -> Set<UUID>
    public let onToggle: () -> Void
    public let onRestart: () -> Void
    public let onSwitchProvider: (UUID) -> Void
    public let onToggleStar: () -> Void
    public let onToggleDisabled: () -> Void
    public let onToggleGroup: (UUID) -> Void
    public let onDuplicate: () -> Void
    public let onCopyConfig: () -> Void
    public let onDelete: () -> Void
    public let onSelect: () -> Void

    public init(
        snapshot: ServiceCardSnapshot,
        runtime: ServiceRuntimeState,
        groupsProvider: @escaping () -> [ServiceGroup] = { [] },
        selectedGroupIDsProvider: @escaping () -> Set<UUID> = { [] },
        onToggle: @escaping () -> Void = {},
        onRestart: @escaping () -> Void = {},
        onSwitchProvider: @escaping (UUID) -> Void = { _ in },
        onToggleStar: @escaping () -> Void = {},
        onToggleDisabled: @escaping () -> Void = {},
        onToggleGroup: @escaping (UUID) -> Void = { _ in },
        onDuplicate: @escaping () -> Void = {},
        onCopyConfig: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onSelect: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.runtime = runtime
        self.groupsProvider = groupsProvider
        self.selectedGroupIDsProvider = selectedGroupIDsProvider
        self.onToggle = onToggle
        self.onRestart = onRestart
        self.onSwitchProvider = onSwitchProvider
        self.onToggleStar = onToggleStar
        self.onToggleDisabled = onToggleDisabled
        self.onToggleGroup = onToggleGroup
        self.onDuplicate = onDuplicate
        self.onCopyConfig = onCopyConfig
        self.onDelete = onDelete
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            executionControlButtons

            Button {
                onRestart()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .disabled(snapshot.isDisabled || runtime.status != .running)

            Divider()

            Button {
                onSelect()
            } label: {
                Label("Open Details", systemImage: "sidebar.right")
            }

            ServiceProviderSwitchSubmenu(snapshot: snapshot, onSwitchProvider: onSwitchProvider)

            ServiceGroupsSubmenu(
                groups: groupsProvider(),
                selectedGroupIDsProvider: selectedGroupIDsProvider,
                onToggleGroup: onToggleGroup
            )

            Button {
                onToggleStar()
            } label: {
                Label(
                    snapshot.isStarred ? "Unstar" : "Star",
                    systemImage: snapshot.isStarred ? "star.fill" : "star"
                )
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button {
                onCopyConfig()
            } label: {
                Label("Copy Config", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                onToggleDisabled()
            } label: {
                Label(snapshot.isDisabled ? "Enable" : "Disable",
                      systemImage: snapshot.isDisabled ? "lock.open.fill" : "lock.slash.fill")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var executionControlButtons: some View {
        if snapshot.isDisabled {
            Button {} label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(true)
        } else if runtime.status == .running || runtime.status == .starting || runtime.status == .reconnecting {
            Button {
                onToggle()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        } else {
            Button {
                onToggle()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
        }
    }
}
