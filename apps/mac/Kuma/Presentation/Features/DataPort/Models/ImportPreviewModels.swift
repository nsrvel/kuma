import Foundation

// MARK: - DataPort Presentation Models

public struct ServiceImportRow: Identifiable, Sendable {
    public let id: UUID
    public var serviceName: String
    public let serviceDescription: String?
    public let providerCategory: ProviderCategory
    public let target: String
    public let hasConflict: Bool
    public let provider: DataPortService.ExportProvider?
    public let portMappings: [DataPortService.ExportPortMapping]

    public init(
        id: UUID,
        serviceName: String,
        serviceDescription: String? = nil,
        providerCategory: ProviderCategory,
        target: String,
        hasConflict: Bool = false,
        provider: DataPortService.ExportProvider? = nil,
        portMappings: [DataPortService.ExportPortMapping] = []
    ) {
        self.id = id
        self.serviceName = serviceName
        self.serviceDescription = serviceDescription
        self.providerCategory = providerCategory
        self.target = target
        self.hasConflict = hasConflict
        self.provider = provider
        self.portMappings = portMappings
    }
}

public struct FullImportTableRow: Identifiable, Sendable {
    public let id: UUID
    public let serviceName: String
    public let serviceDescription: String?
    public let workspaceName: String
    public let workspaceID: UUID
    public let providerCategory: ProviderCategory
    public let target: String
    public let isExistingWorkspace: Bool
    public let provider: DataPortService.ExportProvider?
    public let portMappings: [DataPortService.ExportPortMapping]

    public init(
        id: UUID,
        serviceName: String,
        serviceDescription: String? = nil,
        workspaceName: String,
        workspaceID: UUID,
        providerCategory: ProviderCategory,
        target: String,
        isExistingWorkspace: Bool,
        provider: DataPortService.ExportProvider? = nil,
        portMappings: [DataPortService.ExportPortMapping] = []
    ) {
        self.id = id
        self.serviceName = serviceName
        self.serviceDescription = serviceDescription
        self.workspaceName = workspaceName
        self.workspaceID = workspaceID
        self.providerCategory = providerCategory
        self.target = target
        self.isExistingWorkspace = isExistingWorkspace
        self.provider = provider
        self.portMappings = portMappings
    }
}
