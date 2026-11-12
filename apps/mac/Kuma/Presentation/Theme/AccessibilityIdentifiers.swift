import Foundation

/// Type-safe accessibility and UI interaction testing identifiers for Kuma (Swift 6).
public enum KumaUIID: Sendable {
    // MARK: - Services Deck & Cards
    public static func serviceCard(_ id: UUID) -> String { "service-card-\(id.uuidString)" }
    public static func serviceStatusDot(_ id: UUID) -> String { "service-status-dot-\(id.uuidString)" }
    public static func servicePortChip(_ port: Int) -> String { "service-port-chip-\(port)" }

    // MARK: - Context Menu Actions
    public static let contextMenuToggle = "context-menu-toggle"
    public static let contextMenuRestart = "context-menu-restart"
    public static let contextMenuOpenDetails = "context-menu-open-details"
    public static let contextMenuSwitchProvider = "context-menu-switch-provider"
    public static let contextMenuGroups = "context-menu-groups"
    public static let contextMenuStar = "context-menu-star"
    public static let contextMenuDuplicate = "context-menu-duplicate"
    public static let contextMenuCopyConfig = "context-menu-copy-config"
    public static let contextMenuDisableEnable = "context-menu-disable-enable"
    public static let contextMenuDelete = "context-menu-delete"

    // MARK: - Sidebar Navigation & Groups
    public static let sidebarAllServices = "sidebar-entry-all-services"
    public static let sidebarStarred = "sidebar-entry-starred"
    public static let sidebarGroupsHeader = "sidebar-entry-groups"
    public static func sidebarGroupRow(_ id: UUID) -> String { "sidebar-group-row-\(id.uuidString)" }
    public static func sidebarDropIndicator(_ id: UUID) -> String { "sidebar-drop-indicator-\(id.uuidString)" }

    // MARK: - Inspector Elements
    public static let inspectorHeader = "inspector-header"
    public static let inspectorStartStopToggle = "inspector-start-stop-toggle"
    public static let inspectorStarButton = "inspector-star-button"
    public static let inspectorRunningBanner = "inspector-running-banner"
    public static let inspectorLiveLogsButton = "inspector-live-logs-button"
    public static let inspectorProvidersSection = "inspector-providers-section"
    public static func inspectorProviderRow(_ id: UUID) -> String { "inspector-provider-row-\(id.uuidString)" }
    public static let inspectorAddProviderButton = "inspector-add-provider-button"
    public static let inspectorDeleteServiceButton = "inspector-delete-service-button"

    // MARK: - Global Alerts & Modals
    public static let alertConfirmButton = "alert-confirm-button"
    public static let alertCancelButton = "alert-cancel-button"
}
