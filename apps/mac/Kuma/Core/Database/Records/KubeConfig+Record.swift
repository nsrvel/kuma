import Foundation
import GRDB

// MARK: - KubeConfig GRDB Record Conformance

nonisolated extension KubeConfig: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "kube_config"

    public nonisolated init(row: Row) throws {
        let idStr: String = row["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let name: String = row["name"]
        let configContent: String = row["configContent"]
        let sourceFilePath: String? = row["sourceFilePath"]
        let createdAt: Date = row["createdAt"]
        let updatedAt: Date = row["updatedAt"]

        self.init(
            id: id,
            name: name,
            configContent: configContent,
            sourceFilePath: sourceFilePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["name"] = name
        container["configContent"] = configContent
        container["sourceFilePath"] = sourceFilePath
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
