import Foundation

// MARK: - Notification Names

extension NSNotification.Name {
    public nonisolated static let kumaOpenSettings = NSNotification.Name("kuma.openSettings")
    public nonisolated static let kumaOpenOnboarding = NSNotification.Name("kuma.openOnboarding")
    public nonisolated static let kumaServiceCreated = NSNotification.Name("kuma.serviceCreated")
    public nonisolated static let kumaServiceUpdated = NSNotification.Name("kuma.serviceUpdated")
    public nonisolated static let kumaServiceDeleted = NSNotification.Name("kuma.serviceDeleted")
    public nonisolated static let kumaCreateServiceRequested = NSNotification.Name("kuma.createServiceRequested")
    public nonisolated static let kumaExportWorkspace = NSNotification.Name("kuma.exportWorkspace")
    public nonisolated static let kumaImportWorkspace = NSNotification.Name("kuma.importWorkspace")
    public nonisolated static let kumaFocusSearch = NSNotification.Name("kuma.focusSearch")
    public nonisolated static let kumaGroupsUpdated = NSNotification.Name("kuma.groupsUpdated")
    public nonisolated static let kumaServiceStateChanged = NSNotification.Name("kuma.serviceStateChanged")
}

// MARK: - Service mutation notification metadata

public enum KumaServiceNotification {
    public nonisolated static let sourceKey = "source"
    public nonisolated static let sourceDeck = "deck"
    public nonisolated static let sourceInspector = "inspector"
    public nonisolated static let sourceExecution = "execution"

    public nonisolated static func postServiceUpdated(serviceID: UUID, source: String) {
        NotificationCenter.default.post(
            name: .kumaServiceUpdated,
            object: serviceID,
            userInfo: [sourceKey: source]
        )
    }
}

