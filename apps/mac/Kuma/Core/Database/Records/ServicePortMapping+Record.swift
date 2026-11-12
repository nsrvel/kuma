import Foundation
import GRDB

// MARK: - ServicePortMapping GRDB Record Conformance

nonisolated extension ServicePortMapping: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "portMapping"

    public nonisolated init(row: Row) throws {
        let idStr: String = row["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let serviceStr: String? = row["serviceID"]
        let serviceID = serviceStr.flatMap(UUID.init)
        let providerStr: String? = row["providerID"]
        let providerID = providerStr.flatMap(UUID.init)
        let localPort: Int = row["localPort"]
        let remotePort: Int = row["remotePort"]
        let protocolType: String = row["protocolType"]

        self.init(
            id: id,
            serviceID: serviceID,
            providerID: providerID,
            localPort: localPort,
            remotePort: remotePort,
            protocolType: protocolType
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["serviceID"] = serviceID?.uuidString
        container["providerID"] = providerID?.uuidString
        container["localPort"] = localPort
        container["remotePort"] = remotePort
        container["protocolType"] = protocolType
    }
}
