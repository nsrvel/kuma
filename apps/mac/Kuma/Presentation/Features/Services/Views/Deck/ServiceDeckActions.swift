import Foundation
import SwiftUI

/// Stable action surface for service cards/table rows — avoids per-card observation of `ServicesDeckViewModel`.
public struct ServiceDeckActions {
    public let workspaceID: UUID
    public let groups: () -> [ServiceGroup]
    public let groupIDsForService: (UUID) -> Set<UUID>
    public let onSelect: (UUID) -> Void
    public let onToggle: (UUID) -> Void
    public let onRestart: (UUID) -> Void
    public let onSwitchProvider: (UUID, UUID) -> Void
    public let onToggleStar: (UUID) -> Void
    public let onToggleDisabled: (UUID) -> Void
    public let onToggleGroup: (UUID, UUID) -> Void
    public let onDuplicate: (UUID) -> Void
    public let onCopyConfig: (UUID) -> Void
    public let onDelete: (UUID) -> Void

    public init(
        workspaceID: UUID,
        groups: @escaping () -> [ServiceGroup],
        groupIDsForService: @escaping (UUID) -> Set<UUID>,
        onSelect: @escaping (UUID) -> Void,
        onToggle: @escaping (UUID) -> Void,
        onRestart: @escaping (UUID) -> Void,
        onSwitchProvider: @escaping (UUID, UUID) -> Void,
        onToggleStar: @escaping (UUID) -> Void,
        onToggleDisabled: @escaping (UUID) -> Void,
        onToggleGroup: @escaping (UUID, UUID) -> Void,
        onDuplicate: @escaping (UUID) -> Void,
        onCopyConfig: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.workspaceID = workspaceID
        self.groups = groups
        self.groupIDsForService = groupIDsForService
        self.onSelect = onSelect
        self.onToggle = onToggle
        self.onRestart = onRestart
        self.onSwitchProvider = onSwitchProvider
        self.onToggleStar = onToggleStar
        self.onToggleDisabled = onToggleDisabled
        self.onToggleGroup = onToggleGroup
        self.onDuplicate = onDuplicate
        self.onCopyConfig = onCopyConfig
        self.onDelete = onDelete
    }

    public var tableHandlers: ServiceTableActionHandlers {
        ServiceTableActionHandlers(
            onToggle: onToggle,
            onRestart: onRestart,
            onSwitchProvider: onSwitchProvider,
            onToggleStar: onToggleStar,
            onToggleDisabled: onToggleDisabled,
            onToggleGroup: onToggleGroup,
            groupIDsForService: groupIDsForService,
            onDuplicate: onDuplicate,
            onCopyConfig: onCopyConfig,
            onDelete: onDelete,
            onSelect: onSelect
        )
    }
}

private struct ServiceDeckActionsKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: ServiceDeckActions? = nil
}

extension EnvironmentValues {
    public var serviceDeckActions: ServiceDeckActions? {
        get { self[ServiceDeckActionsKey.self] }
        set { self[ServiceDeckActionsKey.self] = newValue }
    }
}

extension ServicesDeckViewModel {
    public func makeDeckActions(workspaceID: UUID) -> ServiceDeckActions {
        ServiceDeckActions(
            workspaceID: workspaceID,
            groups: { [self] in self.groups },
            groupIDsForService: { [self] serviceID in
                self.snapshots.first(where: { $0.id == serviceID })?.groupIDs ?? []
            },
            onSelect: { [self] id in self.selectService(id) },
            onToggle: { [self] id in self.toggleService(id: id) },
            onRestart: { [self] id in self.restartService(id: id) },
            onSwitchProvider: { [self] serviceID, providerID in
                self.switchProvider(serviceID: serviceID, providerID: providerID, workspaceID: workspaceID)
            },
            onToggleStar: { [self] id in self.toggleStarred(id: id, workspaceID: workspaceID) },
            onToggleDisabled: { [self] id in self.toggleDisabled(id: id, workspaceID: workspaceID) },
            onToggleGroup: { [self] serviceID, groupID in
                self.toggleGroup(serviceID: serviceID, groupID: groupID, workspaceID: workspaceID)
            },
            onDuplicate: { [self] id in self.duplicateService(id: id, workspaceID: workspaceID) },
            onCopyConfig: { [self] id in self.copyConfig(id: id) },
            onDelete: { [self] id in self.promptDeleteService(id: id) }
        )
    }
}
