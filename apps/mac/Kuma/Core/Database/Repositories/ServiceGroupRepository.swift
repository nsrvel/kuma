import Foundation
import GRDB

public protocol ServiceGroupRepositoryProtocol: Sendable {
    func fetchAll(workspaceID: UUID) async throws -> [ServiceGroup]
    func insert(_ group: ServiceGroup) async throws
    func update(_ group: ServiceGroup) async throws
    func updateSortOrders(_ orders: [(id: UUID, sortOrder: Int)]) async throws
    func delete(id: UUID) async throws
}

/// `@unchecked Sendable`: Thread safety is guaranteed by GRDB's underlying `DatabaseWriter` (DatabasePool / DatabaseQueue)
/// which synchronizes access via serialized dispatch queues. Do not add mutable stored properties to this class.
public final class ServiceGroupRepository: ServiceGroupRepositoryProtocol, @unchecked Sendable {
    private let dbWriter: any DatabaseWriter

    public nonisolated init(dbWriter: (any DatabaseWriter)? = nil) {
        self.dbWriter = dbWriter ?? AppDatabase.shared.dbWriter
    }

    public func fetchAll(workspaceID: UUID) async throws -> [ServiceGroup] {
        try await dbWriter.read { db in
            try ServiceGroup
                .filter(Column("workspaceID") == workspaceID.uuidString)
                .order(Column("sortOrder").asc, Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func insert(_ group: ServiceGroup) async throws {
        try await dbWriter.write { db in
            try group.insert(db)
        }
    }

    public func update(_ group: ServiceGroup) async throws {
        try await dbWriter.write { db in
            try group.update(db)
        }
    }

    public func updateSortOrders(_ orders: [(id: UUID, sortOrder: Int)]) async throws {
        try await dbWriter.write { db in
            for item in orders {
                try db.execute(
                    sql: "UPDATE service_group SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                    arguments: [item.sortOrder, Date(), item.id.uuidString]
                )
            }
        }
    }

    public func delete(id: UUID) async throws {
        try await dbWriter.write { db in
            _ = try ServiceGroup.deleteOne(db, key: id.uuidString)
        }
    }
}
