import Foundation
import GRDB

public protocol ServiceRepositoryProtocol: Sendable {
    func fetchDeckItems(forWorkspace workspaceID: UUID) async throws -> [ServiceDeckItem]
    func fetchDeckItem(serviceID: UUID) async throws -> ServiceDeckItem?
    func fetchService(id: UUID) async throws -> Service?
    func fetchServiceDetail(id: UUID) async throws -> (service: Service, providers: [Provider], portMappings: [ServicePortMapping])?
    func fetchProviders(forService serviceID: UUID) async throws -> [Provider]
    func fetchPortMappings(forService serviceID: UUID) async throws -> [ServicePortMapping]
    func fetchPortMappings(forService serviceID: UUID, providerID: UUID) async throws -> [ServicePortMapping]
    func fetchAllPortMappings() async throws -> [ServicePortMapping]
    func insertService(_ service: Service, defaultProvider: Provider?, portMappings: [ServicePortMapping]) async throws
    func updateService(_ service: Service) async throws
    func insertProvider(_ provider: Provider) async throws
    func updateProvider(_ provider: Provider) async throws
    func deleteProvider(id: UUID) async throws
    func savePortMappings(_ portMappings: [ServicePortMapping], forService serviceID: UUID, providerID: UUID) async throws
    func toggleStarred(serviceID: UUID) async throws -> Bool
    func toggleGroupMembership(serviceID: UUID, groupID: UUID) async throws -> Set<UUID>
    func deleteService(id: UUID) async throws
    func duplicateService(sourceID: UUID, newID: UUID) async throws -> Service
}


/// `@unchecked Sendable`: Thread safety is guaranteed by GRDB's underlying `DatabaseWriter` (DatabasePool / DatabaseQueue)
/// which synchronizes access via serialized dispatch queues. Do not add mutable stored properties to this class.
public final class ServiceRepository: ServiceRepositoryProtocol, @unchecked Sendable {
    let dbWriter: any DatabaseWriter


    public nonisolated init(dbWriter: (any DatabaseWriter)? = nil) {
        self.dbWriter = dbWriter ?? AppDatabase.shared.dbWriter
    }
}
