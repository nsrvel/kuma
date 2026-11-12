import Foundation

public enum DependencyCategory: String, Sendable {
    case engine     // Kubernetes, Docker, Podman
    case tunneling  // Cloudflare Tunnel, ngrok
}

public struct SystemDependency: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let iconName: String
    public let isInstalled: Bool
    public let path: String?
    public let version: String?
    public let category: DependencyCategory
    public let description: String
    public let settingsKey: String

    public nonisolated init(
        id: String,
        name: String,
        iconName: String,
        isInstalled: Bool,
        path: String? = nil,
        version: String? = nil,
        category: DependencyCategory = .engine,
        description: String = "",
        settingsKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isInstalled = isInstalled
        self.path = path
        self.version = version
        self.category = category
        self.description = description
        self.settingsKey = settingsKey
    }
}
