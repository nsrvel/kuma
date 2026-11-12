import Foundation
import GRDB

public struct ServiceGroupMembershipRecord: FetchableRecord, PersistableRecord, Sendable {
    public nonisolated static let databaseTableName = "service_group_membership"

    public let serviceID: UUID
    public let groupID: UUID
    public let createdAt: Date

    public nonisolated init(serviceID: UUID, groupID: UUID, createdAt: Date = Date()) {
        self.serviceID = serviceID
        self.groupID = groupID
        self.createdAt = createdAt
    }

    public nonisolated init(row: Row) throws {
        let sIdStr: String = row["serviceID"]
        let gIdStr: String = row["groupID"]
        self.serviceID = UUID(uuidString: sIdStr) ?? UUID()
        self.groupID = UUID(uuidString: gIdStr) ?? UUID()
        self.createdAt = row["createdAt"]
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["serviceID"] = serviceID.uuidString
        container["groupID"] = groupID.uuidString
        container["createdAt"] = createdAt
    }
}
