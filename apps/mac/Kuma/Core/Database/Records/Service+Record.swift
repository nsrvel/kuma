import Foundation
import GRDB

// MARK: - Service GRDB Record Conformance

nonisolated extension Service: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "service"

    public nonisolated init(row: Row) throws {
        let idStr: String = row["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let wsStr: String? = row["workspaceID"]
        let workspaceID = wsStr.flatMap(UUID.init)
        let name: String = row["name"]
        let icon: String? = row["icon"]
        let colorHex: String? = row["colorHex"]
        let description: String? = row["description"]
        let activeProvStr: String? = row["activeProviderID"]
        let activeProviderID = activeProvStr.flatMap(UUID.init)
        let isDisabled: Bool = row["isDisabled"]
        let isStarred: Bool = row["isStarred"] ?? false
        let createdAt: Date = row["createdAt"]
        let updatedAt: Date = row["updatedAt"]

        self.init(
            id: id,
            name: name,
            icon: icon,
            colorHex: colorHex,
            description: description,
            activeProviderID: activeProviderID,
            workspaceID: workspaceID,
            groupIDs: [],
            isDisabled: isDisabled,
            isStarred: isStarred,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["workspaceID"] = workspaceID?.uuidString
        container["name"] = name
        container["icon"] = icon
        container["colorHex"] = colorHex
        container["description"] = description
        container["activeProviderID"] = activeProviderID?.uuidString
        container["isDisabled"] = isDisabled
        container["isStarred"] = isStarred
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
