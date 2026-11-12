import Foundation
import GRDB
@testable import Kuma

/// Isolated in-memory SQLite Test Harness for Feature 05: DataPort (Backup, Export, Import, Reset).
@MainActor
public final class DataPortTestHarness {
    public let databaseQueue: DatabaseQueue
    public let repository: DataPortRepository
    public let defaultWorkspaceID: UUID
    public let tempDirectoryURL: URL

    public init() {
        let wsID = UUID()
        self.defaultWorkspaceID = wsID

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("KumaDataPortTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempDirectoryURL = tempDir

        var config = Configuration()
        config.qos = .userInitiated
        config.prepareDatabase { db in
            try? db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try! DatabaseQueue(configuration: config)

        var migrator = DatabaseMigrator()

        // 1. Production Schema Base
        migrator.registerMigration("v1_production_schema") { db in
            try db.create(table: "workspace") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("imagePath", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "kube_config") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("configContent", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "service") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).notNull().references("workspace", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("colorHex", .text)
                t.column("description", .text)
                t.column("activeProviderID", .text)
                t.column("isDisabled", .boolean).notNull().defaults(to: false)
                t.column("isStarred", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "provider") { t in
                t.column("id", .text).primaryKey()
                t.column("serviceID", .text).notNull().references("service", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("label", .text)
                t.column("kubeConfigID", .text)
                t.column("kubeContext", .text)
                t.column("kubeNamespace", .text)
                t.column("targetName", .text)
                t.column("kubeTargetType", .text)
                t.column("usePattern", .boolean)
                t.column("yamlConfig", .text)
                t.column("initialScript", .text)
                t.column("runCommand", .text)
                t.column("workingDirectory", .text)
                t.column("sshHost", .text)
                t.column("sshUser", .text)
                t.column("sshPort", .integer)
                t.column("sshKeyPath", .text)
                t.column("sshPassword", .text)
                t.column("httpCheckUrl", .text)
                t.column("httpCheckInterval", .integer)
                t.column("tunnelType", .text)
                t.column("tunnelTargetUrl", .text)
                t.column("ngrokAuthToken", .text)
                t.column("monitorProcessName", .text)
                t.column("monitorInterval", .integer)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "portMapping") { t in
                t.column("id", .text).primaryKey()
                t.column("serviceID", .text).notNull().references("service", onDelete: .cascade)
                t.column("localPort", .integer).notNull()
                t.column("remotePort", .integer).notNull()
                t.column("protocolType", .text).notNull().defaults(to: "TCP")
            }
        }

        // 2. Service Groups Migration
        migrator.registerMigration("v2_service_groups") { db in
            try db.create(table: "service_group") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).notNull().references("workspace", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.alter(table: "service") { t in
                t.add(column: "groupID", .text).references("service_group", onDelete: .setNull)
            }
        }

        // 3. Service Group Memberships Join Table
        migrator.registerMigration("v3_service_group_memberships") { db in
            try db.create(table: "service_group_membership") { t in
                t.column("serviceID", .text).notNull().references("service", onDelete: .cascade)
                t.column("groupID", .text).notNull().references("service_group", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["serviceID", "groupID"])
            }
        }

        // 4. Provider Custom Kubeconfig Migration
        migrator.registerMigration("v4_provider_custom_kubeconfig") { db in
            try db.alter(table: "provider") { t in
                t.add(column: "customKubeConfigPath", .text)
            }
        }

        migrator.registerMigration("v5_port_mapping_provider") { db in
            try db.alter(table: "portMapping") { t in
                t.add(column: "providerID", .text).references("provider", onDelete: .cascade)
            }
        }

        migrator.registerMigration("v6_provider_compose_and_script_paths") { db in
            try db.alter(table: "provider") { t in
                t.add(column: "composeFilePath", .text)
                t.add(column: "initialScriptPath", .text)
            }
        }

        migrator.registerMigration("v7_kube_config_source_path") { db in
            try db.alter(table: "kube_config") { t in
                t.add(column: "sourceFilePath", .text)
            }
        }

        migrator.registerMigration("v8_provider_auto_reconnect") { db in
            try db.alter(table: "provider") { t in
                t.add(column: "autoReconnect", .boolean).notNull().defaults(to: false)
            }
        }

        try! migrator.migrate(queue)

        // Seed default workspace
        try! queue.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (id, name, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [wsID.uuidString, "Default Space", 0, Date(), Date()]
            )
        }

        self.databaseQueue = queue
        self.repository = DataPortRepository(dbWriter: queue)
    }

    public func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    // MARK: - Seeding Utilities

    public func seedWorkspace(id: UUID = UUID(), name: String, imagePath: String? = nil, sortOrder: Int = 0) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO workspace (id, name, imagePath, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [id.uuidString, name, imagePath, sortOrder, Date(), Date()]
            )
        }
    }

    public func seedGroup(id: UUID = UUID(), workspaceID: UUID, name: String, sortOrder: Int = 0) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO service_group (id, workspaceID, name, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [id.uuidString, workspaceID.uuidString, name, sortOrder, Date(), Date()]
            )
        }
    }

    public func seedService(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        activeProviderID: UUID? = nil,
        groupIDs: [UUID] = [],
        isDisabled: Bool = false,
        isStarred: Bool = false
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO service (id, workspaceID, name, activeProviderID, isDisabled, isStarred, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                arguments: [id.uuidString, workspaceID.uuidString, name, activeProviderID?.uuidString, isDisabled, isStarred, Date(), Date()]
            )
            for gID in groupIDs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO service_group_membership (serviceID, groupID, createdAt) VALUES (?, ?, ?)",
                    arguments: [id.uuidString, gID.uuidString, Date()]
                )
            }
        }
    }

    public func seedProvider(
        id: UUID = UUID(),
        serviceID: UUID,
        type: String = "docker",
        label: String? = nil,
        yamlConfig: String? = nil,
        runCommand: String? = nil,
        kubeConfigID: UUID? = nil,
        kubeContext: String? = nil,
        targetName: String? = nil
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO provider (
                    id, serviceID, type, label, yamlConfig, runCommand,
                    kubeConfigID, kubeContext, targetName, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id.uuidString, serviceID.uuidString, type, label, yamlConfig, runCommand,
                    kubeConfigID?.uuidString, kubeContext, targetName, Date(), Date()
                ]
            )
        }
    }

    public func seedKubeConfig(
        id: UUID = UUID(),
        name: String,
        encryptedContent: String,
        sourceFilePath: String? = nil
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO kube_config (id, name, configContent, sourceFilePath, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [id.uuidString, name, encryptedContent, sourceFilePath, Date(), Date()]
            )
        }
    }

    public func seedPortMapping(
        id: UUID = UUID(),
        serviceID: UUID,
        providerID: UUID? = nil,
        localPort: Int,
        remotePort: Int
    ) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO portMapping (id, serviceID, providerID, localPort, remotePort, protocolType)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [id.uuidString, serviceID.uuidString, providerID?.uuidString, localPort, remotePort, "TCP"]
            )
        }
    }

    public func fetchCount(table: String) throws -> Int {
        try databaseQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
    }
}
