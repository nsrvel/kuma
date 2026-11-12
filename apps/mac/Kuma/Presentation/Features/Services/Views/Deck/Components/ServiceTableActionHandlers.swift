import Foundation

/// Callback bundle for ServiceTableView actions.
public struct ServiceTableActionHandlers {
    public let onToggle: (UUID) -> Void
    public let onRestart: (UUID) -> Void
    public let onSwitchProvider: (UUID, UUID) -> Void
    public let onToggleStar: (UUID) -> Void
    public let onToggleDisabled: (UUID) -> Void
    public let onToggleGroup: (UUID, UUID) -> Void
    public let groupIDsForService: (UUID) -> Set<UUID>
    public let onDuplicate: (UUID) -> Void
    public let onCopyConfig: (UUID) -> Void
    public let onDelete: (UUID) -> Void
    public let onSelect: (UUID) -> Void

    public init(
        onToggle: @escaping (UUID) -> Void,
        onRestart: @escaping (UUID) -> Void = { _ in },
        onSwitchProvider: @escaping (UUID, UUID) -> Void = { _, _ in },
        onToggleStar: @escaping (UUID) -> Void = { _ in },
        onToggleDisabled: @escaping (UUID) -> Void = { _ in },
        onToggleGroup: @escaping (UUID, UUID) -> Void = { _, _ in },
        groupIDsForService: @escaping (UUID) -> Set<UUID> = { _ in [] },
        onDuplicate: @escaping (UUID) -> Void = { _ in },
        onCopyConfig: @escaping (UUID) -> Void = { _ in },
        onDelete: @escaping (UUID) -> Void = { _ in },
        onSelect: @escaping (UUID) -> Void
    ) {
        self.onToggle = onToggle
        self.onRestart = onRestart
        self.onSwitchProvider = onSwitchProvider
        self.onToggleStar = onToggleStar
        self.onToggleDisabled = onToggleDisabled
        self.onToggleGroup = onToggleGroup
        self.groupIDsForService = groupIDsForService
        self.onDuplicate = onDuplicate
        self.onCopyConfig = onCopyConfig
        self.onDelete = onDelete
        self.onSelect = onSelect
    }
}
