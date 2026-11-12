import Foundation
import Testing
@testable import Kuma

@Suite("Feature 03 - Category A: Initial State & Baseline Contracts", .serialized)
@MainActor
struct WorkspaceInitialStateTests {

    // MARK: - [TC-A01] Fresh boot seeds default workspace
    @Test("TC-A01: Fresh boot with empty database automatically seeds default workspace")
    func testFreshBootSeedsDefaultWorkspace() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let store = WorkspaceStore(repository: harness.repository, userDefaults: harness.userDefaults)
        for _ in 0..<30 {
            if !store.workspaces.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.workspaces.count == 1)
        let first = try #require(store.workspaces.first)
        #expect(!first.name.isEmpty)
        #expect(first.sortOrder == 0)
    }

    // MARK: - [TC-A02] Default workspace persists to database
    @Test("TC-A02: Default workspace record is written to SQLite table")
    func testDefaultWorkspacePersistsToDB() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let store = WorkspaceStore(repository: harness.repository, userDefaults: harness.userDefaults)
        for _ in 0..<30 {
            if !store.workspaces.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces.count == 1)
        #expect(dbWorkspaces.first?.id == store.workspaces.first?.id)
        #expect(dbWorkspaces.first?.name == store.workspaces.first?.name)
    }

    // MARK: - [TC-A03] Default workspace selected on first boot
    @Test("TC-A03: Default workspace is selected and resolves to activeWorkspace")
    func testDefaultWorkspaceSelected() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let store = WorkspaceStore(repository: harness.repository, userDefaults: harness.userDefaults)
        for _ in 0..<30 {
            if store.selectedWorkspaceId != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.selectedWorkspaceId != nil)
        #expect(store.selectedWorkspaceId == store.workspaces.first?.id)
        #expect(store.activeWorkspace?.id == store.workspaces.first?.id)
    }

    // MARK: - [TC-A04] Existing workspaces loaded in sortOrder
    @Test("TC-A04: Pre-existing workspaces in DB are loaded ordered by sortOrder ASC")
    func testExistingWorkspacesLoadedInSortOrder() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let wsB = Workspace(name: "Backend", sortOrder: 1)
        let wsA = Workspace(name: "Frontend", sortOrder: 0)
        let wsC = Workspace(name: "DevOps", sortOrder: 2)

        try await harness.repository.insert(wsB)
        try await harness.repository.insert(wsA)
        try await harness.repository.insert(wsC)

        let store = WorkspaceStore(repository: harness.repository, userDefaults: harness.userDefaults)
        for _ in 0..<30 {
            if store.workspaces.count == 3 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.workspaces.count == 3)
        #expect(store.workspaces[0].name == "Frontend")
        #expect(store.workspaces[1].name == "Backend")
        #expect(store.workspaces[2].name == "DevOps")
    }

    // MARK: - [TC-A05] Persisted selected workspace restored
    @Test("TC-A05: Persisted selectedWorkspaceId in UserDefaults is restored on launch")
    func testPersistedSelectedWorkspaceRestored() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "WS 1", sortOrder: 0)
        let ws2 = Workspace(name: "WS 2", sortOrder: 1)
        try await harness.repository.insert(ws1)
        try await harness.repository.insert(ws2)

        harness.userDefaults.set(ws2.id.uuidString, forKey: WorkspaceStore.selectedWorkspaceKey)

        let store = WorkspaceStore(repository: harness.repository, userDefaults: harness.userDefaults)
        for _ in 0..<30 {
            if store.selectedWorkspaceId == ws2.id { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.selectedWorkspaceId == ws2.id)
        #expect(store.activeWorkspace?.name == "WS 2")
    }

    // MARK: - [TC-A06] Corrupted saved workspace ID falls back to first
    @Test("TC-A06: Corrupted or non-existent saved workspace ID falls back to first workspace")
    func testCorruptedSavedWorkspaceIdFallsBackToFirst() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "WS 1", sortOrder: 0)
        try await harness.repository.insert(ws1)

        // Set non-existent UUID in defaults
        let randomID = UUID().uuidString
        harness.userDefaults.set(randomID, forKey: WorkspaceStore.selectedWorkspaceKey)

        let store = WorkspaceStore(repository: harness.repository, userDefaults: harness.userDefaults)
        for _ in 0..<30 {
            if store.selectedWorkspaceId == ws1.id { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.selectedWorkspaceId == ws1.id)
        #expect(store.activeWorkspace?.id == ws1.id)
    }
}
