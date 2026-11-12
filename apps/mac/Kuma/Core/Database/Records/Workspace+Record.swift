import Foundation
import GRDB

// MARK: - Workspace GRDB Record Conformance

nonisolated extension Workspace: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "workspace"

    public nonisolated init(row: Row) throws {
        let idStr: String = row["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let name: String = row["name"]
        let imagePath: String? = row["imagePath"]
        let sortOrder: Int = row["sortOrder"]
        let createdAt: Date = row["createdAt"]
        let updatedAt: Date = row["updatedAt"]

        self.init(
            id: id,
            name: name,
            imagePath: imagePath,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["name"] = name
        container["imagePath"] = imagePath
        container["sortOrder"] = sortOrder
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
