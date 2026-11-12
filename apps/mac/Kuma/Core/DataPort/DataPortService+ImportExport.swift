import Foundation

extension DataPortService {
    // MARK: - Scopes & Polymorphic Ingestion

    public enum DataPortScope: Sendable, Equatable {
        case all
        case workspace(UUID)
        case service(UUID)
    }

    public enum DataPortImportStrategy: Sendable {
        case preserveOrMerge
        case reassignIDs(targetWorkspaceID: UUID)
    }

    /// Converts a standalone single-service export payload into standard KumaBackup representation.
    public static func wrapSingleService(_ singleExport: SingleServiceExport, targetWorkspaceID: UUID? = nil) -> KumaBackup {
        var service = singleExport.service
        if let targetWorkspaceID {
            service = ExportService(
                id: service.id,
                name: service.name,
                icon: service.icon,
                colorHex: service.colorHex,
                description: service.description,
                activeProviderID: service.activeProviderID,
                workspaceID: targetWorkspaceID,
                groupIDs: service.groupIDs,
                isDisabled: service.isDisabled,
                isStarred: service.isStarred
            )
        }

        return KumaBackup(
            version: singleExport.version,
            exportedAt: singleExport.exportedAt,
            workspaces: [],
            workspaceImages: nil,
            groups: nil,
            services: [service],
            providers: singleExport.providers,
            portMappings: singleExport.portMappings,
            kubeConfigs: singleExport.kubeConfigs
        )
    }

    /// Polymorphic parser that handles both full KumaBackup and SingleServiceExport gracefully.
    public static func parseAnyBackup(from data: Data, targetWorkspaceID: UUID? = nil) throws -> KumaBackup {
        if let backup = try? decodeBackup(from: data) {
            return backup
        }
        if let singleService = try? decodeSingleService(from: data) {
            return wrapSingleService(singleService, targetWorkspaceID: targetWorkspaceID)
        }
        // If both fail, re-run decodeBackup to throw the descriptive JSON decoding error or version error
        return try decodeBackup(from: data)
    }

    // MARK: - Export & Import Engine

    public static func encodeBackup(_ backup: KumaBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decodeBackup(from data: Data) throws -> KumaBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(KumaBackup.self, from: data)

        guard backup.version <= currentVersion else {
            throw DataPortError.unsupportedFutureVersion(backupVersion: backup.version, currentVersion: currentVersion)
        }

        return backup
    }

    public static func encodeSingleService(_ item: SingleServiceExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(item)
    }

    public static func decodeSingleService(from data: Data) throws -> SingleServiceExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SingleServiceExport.self, from: data)
    }

    /// Standardized ISO formatted date suffix for backup filenames (e.g. "2026-08-15")
    public static var backupDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

}
