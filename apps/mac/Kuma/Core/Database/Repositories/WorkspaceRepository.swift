import Foundation
import GRDB

public protocol WorkspaceRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [Workspace]
    func insert(_ workspace: Workspace) async throws
    func update(_ workspace: Workspace) async throws
    func updateSortOrders(_ orders: [(id: UUID, sortOrder: Int)]) async throws
    func delete(id: UUID) async throws
}

/// `@unchecked Sendable`: Thread safety is guaranteed by GRDB's underlying `DatabaseWriter` (DatabasePool / DatabaseQueue)
/// which synchronizes access via serialized dispatch queues. Do not add mutable stored properties to this class.
public final class WorkspaceRepository: WorkspaceRepositoryProtocol, @unchecked Sendable {
    private let dbWriter: any DatabaseWriter


    public nonisolated init(dbWriter: (any DatabaseWriter)? = nil) {
        self.dbWriter = dbWriter ?? AppDatabase.shared.dbWriter
    }

    public func fetchAll() async throws -> [Workspace] {
        try await dbWriter.read { db in
            try Workspace
                .order(Column("sortOrder").asc, Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func insert(_ workspace: Workspace) async throws {
        try await dbWriter.write { db in
            try workspace.insert(db)
        }
    }

    public func update(_ workspace: Workspace) async throws {
        try await dbWriter.write { db in
            try workspace.update(db)
        }
    }

    public func updateSortOrders(_ orders: [(id: UUID, sortOrder: Int)]) async throws {
        try await dbWriter.write { db in
            for item in orders {
                try db.execute(
                    sql: "UPDATE workspace SET sortOrder = ?, updatedAt = ? WHERE id = ?",
                    arguments: [item.sortOrder, Date(), item.id.uuidString]
                )
            }
        }
    }

    public func delete(id: UUID) async throws {
        try await dbWriter.write { db in
            _ = try Workspace.deleteOne(db, key: id.uuidString)
        }
    }
}
