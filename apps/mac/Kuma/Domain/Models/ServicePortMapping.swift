import Foundation

public nonisolated struct ServicePortMapping: Identifiable, Codable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var serviceID: UUID?
    /// Owner provider; each provider on a service may have its own port-forward mappings.
    public var providerID: UUID?
    public var localPort: Int
    public var remotePort: Int
    public var protocolType: String

    public nonisolated init(
        id: UUID = UUID(),
        serviceID: UUID? = nil,
        providerID: UUID? = nil,
        localPort: Int,
        remotePort: Int,
        protocolType: String = "TCP"
    ) {
        self.id = id
        self.serviceID = serviceID
        self.providerID = providerID
        self.localPort = localPort
        self.remotePort = remotePort
        self.protocolType = protocolType
    }

    public nonisolated var displayString: String {
        "\(localPort):\(remotePort)"
    }
}
