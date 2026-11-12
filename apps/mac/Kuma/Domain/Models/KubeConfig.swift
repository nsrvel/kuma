import Foundation

// MARK: - KubeConfig Domain Model

public nonisolated struct KubeConfig: Identifiable, Codable, Sendable, Equatable, Hashable {
    /// Reserved static ID for the system default kubeconfig (~/.kube/config)
    public nonisolated static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public var id: UUID
    public var name: String
    public var configContent: String // YAML plaintext in memory; ciphertext in SQLite
    /// When set, kubectl uses this file on disk instead of materialized DB content.
    public var sourceFilePath: String?
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public nonisolated init(
        id: UUID = UUID(),
        name: String,
        configContent: String,
        sourceFilePath: String? = nil,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.configContent = configContent
        self.sourceFilePath = sourceFilePath
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Plain kubeconfig YAML for parsing/validation (file-backed or inline).
    public nonisolated func resolvedPlainYAML() -> String {
        if let path = sourceFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let expanded = NSString(string: path).expandingTildeInPath
            return (try? String(contentsOfFile: expanded, encoding: .utf8)) ?? ""
        }
        return configContent
    }
}
