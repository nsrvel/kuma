import Foundation
import GRDB
@testable import Kuma

/// Isolated in-memory SQLite Test Harness for Feature 04: Sidebar & Service Groups.
@MainActor
public final class SidebarTestHarness {
    public let databaseQueue: DatabaseQueue
    public let repository: ServiceGroupRepository
    public let workspaceID: UUID

    public init() {
        let wsID = UUID()
        self.workspaceID = wsID

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

            try db.create(table: "service") { t in
                t.column("id", .text).primaryKey()
                t.column("workspaceID", .text).notNull().references("workspace", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("isDisabled", .boolean).notNull().defaults(to: false)
                t.column("isStarred", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
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

        try! migrator.migrate(queue)

        // Seed default workspace
        try! queue.write { db in
            try db.execute(
                sql: "INSERT INTO workspace (id, name, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [wsID.uuidString, "Default Space", 0, Date(), Date()]
            )
        }

        self.databaseQueue = queue
        self.repository = ServiceGroupRepository(dbWriter: queue)
    }

    /// Helper to seed an arbitrary workspace for multi-workspace testing
    public func seedWorkspace(id: UUID, name: String = "Test Workspace") throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO workspace (id, name, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [id.uuidString, name, 0, Date(), Date()]
            )
        }
    }

    /// Seeds a mock service inside the active workspace
    public func seedService(id: UUID = UUID(), name: String, groupID: UUID? = nil) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "INSERT INTO service (id, workspaceID, name, groupID, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [id.uuidString, self.workspaceID.uuidString, name, groupID?.uuidString, Date(), Date()]
            )
            if let groupID {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO service_group_membership (serviceID, groupID, createdAt) VALUES (?, ?, ?)",
                    arguments: [id.uuidString, groupID.uuidString, Date()]
                )
            }
        }
    }

    /// Fetches all services belonging to the active workspace
    public func fetchServiceCount() throws -> Int {
        try databaseQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM service WHERE workspaceID = ?", arguments: [self.workspaceID.uuidString]) ?? 0
        }
    }
}
