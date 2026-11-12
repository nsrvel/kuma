import Foundation
import Testing
import GRDB
@testable import Kuma

@Suite("Feature 03 - Category C: Concurrency, Mutations & Database Mutations (GRDB)", .serialized)
@MainActor
struct WorkspacePersistenceAndSyncTests {

    // MARK: - [TC-C01] Add workspace inserts record and selects it
    @Test("TC-C01: addWorkspace appends to memory, persists to SQLite, and updates active selection")
    func testAddWorkspaceInsertsRecordAndSelects() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let initialWS = Workspace(name: "Starter")
        try await harness.repository.insert(initialWS)

        let store = WorkspaceStore(initialWorkspaces: [initialWS], repository: harness.repository, userDefaults: harness.userDefaults)
        let added = store.addWorkspace(name: "New Project")

        #expect(store.workspaces.count == 2)
        #expect(store.selectedWorkspaceId == added.id)
        #expect(store.activeWorkspace?.name == "New Project")

        try await Task.sleep(nanoseconds: 60_000_000)
        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces.count == 2)
        #expect(dbWorkspaces.contains(where: { $0.id == added.id }))
    }

    // MARK: - [TC-C02] Rename workspace updates record
    @Test("TC-C02: renameWorkspace updates in-memory array and SQLite record")
    func testRenameWorkspaceUpdatesRecord() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws = Workspace(name: "Old Name")
        try await harness.repository.insert(ws)

        let store = WorkspaceStore(initialWorkspaces: [ws], repository: harness.repository, userDefaults: harness.userDefaults)
        store.renameWorkspace(ws, newName: "Renamed Space")

        #expect(store.workspaces.first?.name == "Renamed Space")

        try await Task.sleep(nanoseconds: 60_000_000)
        let fetched = try await harness.repository.fetchAll()
        #expect(fetched.first?.name == "Renamed Space")
    }

    // MARK: - [TC-C03] Delete workspace removes record
    @Test("TC-C03: deleteWorkspace removes from memory and SQLite table")
    func testDeleteWorkspaceRemovesRecord() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "Workspace 1", sortOrder: 0)
        let ws2 = Workspace(name: "Workspace 2", sortOrder: 1)
        try await harness.repository.insert(ws1)
        try await harness.repository.insert(ws2)

        let store = WorkspaceStore(initialWorkspaces: [ws1, ws2], repository: harness.repository, userDefaults: harness.userDefaults)
        store.deleteWorkspace(ws2)

        #expect(store.workspaces.count == 1)
        #expect(store.workspaces.first?.id == ws1.id)

        try await Task.sleep(nanoseconds: 60_000_000)
        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces.count == 1)
        #expect(dbWorkspaces.first?.id == ws1.id)
    }

    // MARK: - [TC-C04] Delete active workspace falls back
    @Test("TC-C04: Deleting currently active workspace automatically falls back to first remaining workspace")
    func testDeleteActiveWorkspaceFallsBack() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "Workspace 1", sortOrder: 0)
        let ws2 = Workspace(name: "Workspace 2", sortOrder: 1)
        try await harness.repository.insert(ws1)
        try await harness.repository.insert(ws2)

        let store = WorkspaceStore(initialWorkspaces: [ws1, ws2], repository: harness.repository, userDefaults: harness.userDefaults)
        store.selectWorkspace(ws2)
        #expect(store.selectedWorkspaceId == ws2.id)

        store.deleteWorkspace(ws2)
        #expect(store.selectedWorkspaceId == ws1.id)
        #expect(store.activeWorkspace?.id == ws1.id)
    }

    // MARK: - [TC-C05] Delete workspace cascades to services
    @Test("TC-C05: Deleting workspace triggers SQLite cascade delete on child service records")
    func testDeleteWorkspaceCascadesToServices() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "Parent WS", sortOrder: 0)
        let ws2 = Workspace(name: "Sibling WS", sortOrder: 1)
        try await harness.repository.insert(ws1)
        try await harness.repository.insert(ws2)

        // Insert child service for ws1
        try await harness.databaseQueue.write { db in
            try db.execute(
                sql: "INSERT INTO service (id, workspaceID, name, isDisabled, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [UUID().uuidString, ws1.id.uuidString, "Child Service", false, Date(), Date()]
            )
        }

        let store = WorkspaceStore(initialWorkspaces: [ws1, ws2], repository: harness.repository, userDefaults: harness.userDefaults)
        store.deleteWorkspace(ws1)

        try await Task.sleep(nanoseconds: 60_000_000)

        let remainingServicesCount = try await harness.databaseQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM service WHERE workspaceID = ?", arguments: [ws1.id.uuidString])
        }
        #expect(remainingServicesCount == 0)
    }

    // MARK: - [TC-C06] Move workspace reorders sortOrder
    @Test("TC-C06: moveWorkspace reorders sortOrder in memory and SQLite atomically")
    func testMoveWorkspaceReordersSortOrder() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let wsA = Workspace(name: "A", sortOrder: 0)
        let wsB = Workspace(name: "B", sortOrder: 1)
        let wsC = Workspace(name: "C", sortOrder: 2)

        try await harness.repository.insert(wsA)
        try await harness.repository.insert(wsB)
        try await harness.repository.insert(wsC)

        let store = WorkspaceStore(initialWorkspaces: [wsA, wsB, wsC], repository: harness.repository, userDefaults: harness.userDefaults)

        // Swap 0 (A) and 2 (C)
        store.moveWorkspace(from: 0, to: 2)

        #expect(store.workspaces[0].name == "C")
        #expect(store.workspaces[0].sortOrder == 0)
        #expect(store.workspaces[1].name == "B")
        #expect(store.workspaces[1].sortOrder == 1)
        #expect(store.workspaces[2].name == "A")
        #expect(store.workspaces[2].sortOrder == 2)

        try await Task.sleep(nanoseconds: 80_000_000)
        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces[0].name == "C")
        #expect(dbWorkspaces[2].name == "A")
    }

    // MARK: - [TC-C07] Concurrent workspace creations
    @Test("TC-C07: Concurrent workspace creation tasks execute cleanly without race conditions")
    func testConcurrentWorkspaceCreations() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let initialWS = Workspace(name: "Main")
        try await harness.repository.insert(initialWS)

        let store = WorkspaceStore(initialWorkspaces: [initialWS], repository: harness.repository, userDefaults: harness.userDefaults)

        for i in 1...5 {
            _ = store.addWorkspace(name: "Concurrent WS \(i)")
        }

        #expect(store.workspaces.count == 6)
        try await Task.sleep(nanoseconds: 120_000_000)

        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces.count == 6)
    }

    // MARK: - [TC-C08] Concurrent reads and writes
    @Test("TC-C08: Concurrent fetchAll during mutations maintains consistent state")
    func testConcurrentWorkspaceReadsAndWrites() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws = Workspace(name: "Test WS")
        try await harness.repository.insert(ws)

        let store = WorkspaceStore(initialWorkspaces: [ws], repository: harness.repository, userDefaults: harness.userDefaults)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                store.renameWorkspace(ws, newName: "Renamed Async")
            }
            group.addTask {
                _ = try? await harness.repository.fetchAll()
            }
        }

        try await Task.sleep(nanoseconds: 60_000_000)
        let finalWS = try await harness.repository.fetchAll()
        #expect(finalWS.first?.name == "Renamed Async")
    }
}
