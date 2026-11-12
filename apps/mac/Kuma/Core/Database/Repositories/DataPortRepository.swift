import Foundation
import GRDB
import os

public protocol DataPortRepositoryProtocol: Sendable {
    func exportData(scope: DataPortService.DataPortScope) async throws -> DataPortService.KumaBackup
    func importData(backup: DataPortService.KumaBackup, strategy: DataPortService.DataPortImportStrategy) async throws
    func exportAll() async throws -> DataPortService.KumaBackup
    func importAll(from backup: DataPortService.KumaBackup) async throws
}

/// `@unchecked Sendable`: Thread safety is guaranteed by GRDB's underlying `DatabaseWriter` (DatabasePool / DatabaseQueue)
/// which synchronizes access via serialized dispatch queues. Do not add mutable stored properties to this class.
public final class DataPortRepository: DataPortRepositoryProtocol, @unchecked Sendable {
    let logger = Logger(subsystem: "lokastudio.kuma", category: "DataPortRepository")
    let dbWriter: any DatabaseWriter

    public nonisolated init(dbWriter: (any DatabaseWriter)? = nil) {
        self.dbWriter = dbWriter ?? AppDatabase.shared.dbWriter
    }

    // MARK: - Unified Scoped Operations

    /// Unified export operation scoped to all, single workspace, or single service.
    public func exportData(scope: DataPortService.DataPortScope) async throws -> DataPortService.KumaBackup {
        switch scope {
        case .all:
            return try await exportAll()
        case .workspace(let wsID):
            return try await exportWorkspace(id: wsID)
        case .service(let serviceID):
            return try await exportSingleServiceBackup(serviceID: serviceID)
        }
    }

    /// Unified import operation applying either preserveOrMerge or reassignIDs strategy.
    public func importData(backup: DataPortService.KumaBackup, strategy: DataPortService.DataPortImportStrategy) async throws {
        switch strategy {
        case .preserveOrMerge:
            try await importAll(from: backup)
        case .reassignIDs(let targetWSID):
            let allServiceIDs = Set(backup.services.map(\.id))
            try await importIntoWorkspace(targetWorkspaceID: targetWSID, backup: backup, selectedServiceIDs: allServiceIDs)
        }
    }
}
