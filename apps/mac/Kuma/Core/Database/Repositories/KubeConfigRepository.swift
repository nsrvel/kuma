import Foundation
import GRDB

public protocol KubeConfigRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [KubeConfig]
    func fetch(id: UUID) async throws -> KubeConfig?
    func insert(_ kubeConfig: KubeConfig) async throws
    func update(_ kubeConfig: KubeConfig) async throws
    func delete(id: UUID) async throws
}

/// `@unchecked Sendable`: Thread safety is guaranteed by GRDB's underlying `DatabaseWriter` (DatabasePool / DatabaseQueue)
/// which synchronizes access via serialized dispatch queues. Do not add mutable stored properties to this class.
public final class KubeConfigRepository: KubeConfigRepositoryProtocol, @unchecked Sendable {
    private let dbWriter: any DatabaseWriter

    public nonisolated init(dbWriter: any DatabaseWriter = AppDatabase.shared.dbWriter) {
        self.dbWriter = dbWriter
    }

    public func fetchAll() async throws -> [KubeConfig] {
        try await dbWriter.read { db in
            try KubeConfig.order(Column("createdAt").asc).fetchAll(db)
        }
    }

    public func fetch(id: UUID) async throws -> KubeConfig? {
        try await dbWriter.read { db in
            try KubeConfig.fetchOne(db, key: id.uuidString)
        }
    }

    public func insert(_ kubeConfig: KubeConfig) async throws {
        try await dbWriter.write { db in
            try kubeConfig.insert(db)
        }
    }

    public func update(_ kubeConfig: KubeConfig) async throws {
        try await dbWriter.write { db in
            try kubeConfig.update(db)
        }
    }

    public func delete(id: UUID) async throws {
        try await dbWriter.write { db in
            _ = try KubeConfig.deleteOne(db, key: id.uuidString)
        }
    }
}
