import Foundation
import GRDB

// MARK: - ServiceGroup GRDB Record Conformance

nonisolated extension ServiceGroup: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "service_group"

    public nonisolated init(row: Row) throws {
        let idStr: String = row["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let wsStr: String? = row["workspaceID"]
        let workspaceID = wsStr.flatMap(UUID.init)
        let name: String = row["name"]
        let sortOrder: Int = row["sortOrder"]
        let createdAt: Date = row["createdAt"]
        let updatedAt: Date = row["updatedAt"]

        self.init(
            id: id,
            name: name,
            workspaceID: workspaceID,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["workspaceID"] = workspaceID?.uuidString
        container["name"] = name
        container["sortOrder"] = sortOrder
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
