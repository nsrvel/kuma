import Foundation
import Testing
import AppKit
@testable import Kuma

@Suite("Feature 03 - Category E: Edge Cases, Quirks & Sole Workspace Protection", .serialized)
@MainActor
struct WorkspaceEdgeCasesAndErrorTests {

    // MARK: - [TC-E01] Sole workspace deletion blocked
    @Test("TC-E01: Deleting the last remaining workspace is strictly blocked by invariant guard")
    func testSoleWorkspaceDeletionBlocked() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let soleWS = Workspace(name: "Sole Space")
        try await harness.repository.insert(soleWS)

        let store = WorkspaceStore(initialWorkspaces: [soleWS], repository: harness.repository, userDefaults: harness.userDefaults)
        #expect(store.workspaces.count == 1)

        // Attempt deletion
        store.deleteWorkspace(soleWS)

        #expect(store.workspaces.count == 1)
        #expect(store.workspaces.first?.id == soleWS.id)

        try await Task.sleep(nanoseconds: 50_000_000)
        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces.count == 1)
    }

    // MARK: - [TC-E02] Missing image file fallback
    @Test("TC-E02: If avatar image is deleted from disk, thumbnail returns nil safely")
    func testMissingImageFileFallbackToInitials() {
        let nonExistentPath = "ghost_image_12345.png"
        let thumb = WorkspaceImageStore.shared.thumbnail(for: nonExistentPath)
        #expect(thumb == nil)
    }

    // MARK: - [TC-E03] Corrupted image file handling
    @Test("TC-E03: Corrupted non-image file returns nil without crashing")
    func testCorruptedImageFileHandling() {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let corruptURL = harness.createCorruptedImageFile()
        let result = WorkspaceImageStore.shared.saveWorkspaceImage(from: corruptURL, workspaceID: UUID())
        #expect(result == nil)
    }

    // MARK: - [TC-E04] Rapid workspace switching stress
    @Test("TC-E04: Rapid selection updates synchronize with UserDefaults safely")
    func testRapidWorkspaceSwitchingStress() {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "WS 1")
        let ws2 = Workspace(name: "WS 2")
        let ws3 = Workspace(name: "WS 3")

        let store = WorkspaceStore(initialWorkspaces: [ws1, ws2, ws3], repository: harness.repository, userDefaults: harness.userDefaults)

        for _ in 0..<50 {
            store.selectWorkspace(ws1)
            store.selectWorkspace(ws2)
            store.selectWorkspace(ws3)
        }

        #expect(store.selectedWorkspaceId == ws3.id)
        #expect(harness.userDefaults.string(forKey: WorkspaceStore.selectedWorkspaceKey) == ws3.id.uuidString)
    }

    // MARK: - [TC-E05] Out of bounds and negative index ignored
    @Test("TC-E05: moveWorkspace rejects negative or out-of-bounds index without crashing")
    func testMoveWorkspaceOutOfBoundsIndexIgnored() {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "A")
        let ws2 = Workspace(name: "B")
        let store = WorkspaceStore(initialWorkspaces: [ws1, ws2], repository: harness.repository, userDefaults: harness.userDefaults)

        // Invalid negative index
        store.moveWorkspace(from: -1, to: 1)
        #expect(store.workspaces[0].name == "A")

        // Invalid upper bound index
        store.moveWorkspace(from: 0, to: 99)
        #expect(store.workspaces[0].name == "A")

        // Same index
        store.moveWorkspace(from: 0, to: 0)
        #expect(store.workspaces[0].name == "A")
    }
}
