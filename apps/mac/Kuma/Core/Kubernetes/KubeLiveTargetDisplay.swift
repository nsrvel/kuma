import Foundation

/// Ephemeral Kubernetes target name chosen at start (pattern match). Never written to SQLite.
enum KubeLiveTargetDisplay: Sendable {
    private nonisolated(unsafe) static let lock = NSLock()
    private nonisolated(unsafe) static var resolvedNames: [UUID: String] = [:]

    nonisolated static func setResolvedName(_ name: String, for serviceID: UUID) {
        lock.lock()
        resolvedNames[serviceID] = name
        lock.unlock()
    }

    nonisolated static func resolvedName(for serviceID: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedNames[serviceID]
    }

    nonisolated static func clear(serviceID: UUID) {
        lock.lock()
        resolvedNames.removeValue(forKey: serviceID)
        lock.unlock()
    }

    nonisolated static func clearAll() {
        lock.lock()
        resolvedNames.removeAll()
        lock.unlock()
    }
}
