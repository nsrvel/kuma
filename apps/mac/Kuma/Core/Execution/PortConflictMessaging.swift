import Foundation

/// Shared copy for port-conflict notifications, errors, and in-app alerts.
public enum PortConflictMessaging: Sendable {
    public static let alertTitle = "Port Conflict Detected"

    public nonisolated static func blockedStartMessage(
        port: Int,
        collidingService: String,
        startingServiceName: String
    ) -> String {
        if port > 0 {
            return "Port \(port) is in use by \(collidingService). Cannot start “\(startingServiceName)” (policy: Warn & Prevent Start)."
        }
        return "A host port is in use by \(collidingService). Cannot start “\(startingServiceName)” (policy: Warn & Prevent Start)."
    }

    public nonisolated static func notificationBody(port: Int, collidingService: String) -> String {
        "Port \(port) is already in use by “\(collidingService)”."
    }

    public nonisolated static func isComposePortConflictMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("port is already allocated") { return true }
        if lower.contains("bind for"), lower.contains("failed") { return true }
        if lower.hasPrefix("port conflict:") { return true }
        return false
    }

    public static func currentPortConflictPolicy(userDefaults: UserDefaults = .standard) -> PortConflictPolicy {
        let raw = userDefaults.string(forKey: KumaSettingsKey.portConflictPolicy)
            ?? PortConflictPolicy.warnAndBlock.rawValue
        return PortConflictPolicy(rawValue: raw) ?? .warnAndBlock
    }
}
