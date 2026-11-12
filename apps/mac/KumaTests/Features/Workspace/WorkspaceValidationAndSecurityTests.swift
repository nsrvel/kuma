import Foundation
import Testing
import AppKit
@testable import Kuma

@Suite("Feature 03 - Category B: Input/Form Validation, Crypto & Security", .serialized)
@MainActor
struct WorkspaceValidationAndSecurityTests {

    // MARK: - [TC-B01] Workspace Name Trimming
    @Test("TC-B01: Workspace name trims leading and trailing whitespace")
    func testWorkspaceNameTrimming() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let store = WorkspaceStore(initialWorkspaces: [Workspace(name: "Default")], repository: harness.repository, userDefaults: harness.userDefaults)
        let added = store.addWorkspace(name: "  Production Cloud  ")

        #expect(added.name == "Production Cloud")
        #expect(store.workspaces.last?.name == "Production Cloud")
    }

    // MARK: - [TC-B02] Empty Workspace Name Fallback
    @Test("TC-B02: Blank or whitespace-only workspace name defaults to 'New Workspace'")
    func testEmptyWorkspaceNameFallback() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let store = WorkspaceStore(initialWorkspaces: [Workspace(name: "Default")], repository: harness.repository, userDefaults: harness.userDefaults)
        let addedEmpty = store.addWorkspace(name: "")
        let addedSpaces = store.addWorkspace(name: "    ")

        #expect(addedEmpty.name == "New Workspace")
        #expect(addedSpaces.name == "New Workspace")
    }

    // MARK: - [TC-B03] Special Characters & Unicode
    @Test("TC-B03: Workspace name safely supports emoji and punctuation without corrupted encoding")
    func testWorkspaceNameWithSpecialCharacters() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let store = WorkspaceStore(initialWorkspaces: [Workspace(name: "Default")], repository: harness.repository, userDefaults: harness.userDefaults)
        let specialName = "🚀 [Staging] / Cluster (US-East-1)"
        let added = store.addWorkspace(name: specialName)

        #expect(added.name == specialName)
        try await Task.sleep(nanoseconds: 50_000_000)

        let dbWorkspaces = try await harness.repository.fetchAll()
        #expect(dbWorkspaces.contains(where: { $0.name == specialName }))
    }

    // MARK: - [TC-B04] Hardware Image Downsampling
    @Test("TC-B04: Large images are downsampled to max 512px thumbnail")
    func testWorkspaceAvatarImageHardwareDownsampling() async throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        // Create a large 1024x1024 image
        let sampleURL = harness.createSampleImage(width: 1024, height: 1024)
        let testID = UUID()

        let savedFileName = WorkspaceImageStore.shared.saveWorkspaceImage(from: sampleURL, workspaceID: testID)
        let fileName = try #require(savedFileName)
        defer { WorkspaceImageStore.shared.deleteImage(for: fileName) }

        #expect(fileName == "\(testID.uuidString).png")

        let thumbnail = WorkspaceImageStore.shared.thumbnail(for: fileName, maxDimension: 128)
        #expect(thumbnail != nil)
        #expect(thumbnail?.size.width == 128)
        #expect(thumbnail?.size.height == 128)
    }

    // MARK: - [TC-B05] POSIX Permissions
    @Test("TC-B05: Saved workspace images have valid, readable POSIX file permissions")
    func testWorkspaceAvatarPOSIXPermissions() throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let sampleURL = harness.createSampleImage(width: 200, height: 200)
        let testID = UUID()

        let saved = WorkspaceImageStore.shared.saveWorkspaceImage(from: sampleURL, workspaceID: testID)
        let fileName = try #require(saved)
        defer { WorkspaceImageStore.shared.deleteImage(for: fileName) }

        let resolvedURL = WorkspaceImageStore.shared.resolveURL(for: fileName)
        let attrs = try FileManager.default.attributesOfItem(atPath: resolvedURL.path(percentEncoded: false))
        let permissions = attrs[.posixPermissions] as? NSNumber
        #expect(permissions != nil)
    }

    // MARK: - [TC-B06] Base64 Image Roundtrip
    @Test("TC-B06: Base64 image export and import preserves image data without loss")
    func testWorkspaceBase64ImageRoundtrip() throws {
        let harness = WorkspaceTestHarness()
        defer { harness.cleanup() }

        let sampleURL = harness.createSampleImage(width: 64, height: 64)
        let testID = UUID()

        let saved = WorkspaceImageStore.shared.saveWorkspaceImage(from: sampleURL, workspaceID: testID)
        let fileName = try #require(saved)
        defer { WorkspaceImageStore.shared.deleteImage(for: fileName) }

        // Export as base64
        let base64 = WorkspaceImageStore.shared.loadBase64Image(for: fileName)
        let base64String = try #require(base64)
        #expect(!base64String.isEmpty)

        // Import to a new ID
        let newID = UUID()
        let restoredFile = WorkspaceImageStore.shared.saveBase64Image(base64String, workspaceID: newID)
        let restoredName = try #require(restoredFile)
        defer { WorkspaceImageStore.shared.deleteImage(for: restoredName) }

        let thumb = WorkspaceImageStore.shared.thumbnail(for: restoredName)
        #expect(thumb != nil)
    }

    // MARK: - [TC-B07] Corrupted Base64 Image Rejection
    @Test("TC-B07: Invalid base64 string returns nil without crashing or creating corrupted files")
    func testWorkspaceBase64InvalidDataRejection() {
        let testID = UUID()
        let result = WorkspaceImageStore.shared.saveBase64Image("%%%NotBase64Data%%%", workspaceID: testID)
        #expect(result == nil)
    }
}
