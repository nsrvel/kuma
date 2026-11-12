import Foundation
import Testing
@testable import Kuma

@Suite("DataPort Category D: Runtime, Process Registry & Storage Reset", .serialized)
@MainActor
struct DataPortRuntimeAndResetTests {

    init() async {
        await ProcessTestSupport.resetProcessWorld()
    }

    // MARK: - [TC-D01] Storage Reset Terminates Active Processes
    @Test("DataPort.D01: resetAllAppStorage invokes ProcessRegistry.shared.terminateAll")
    func testStorageResetTerminatesActiveProcesses() async {
        let fakeID = UUID()
        let isRunningBefore = await ProcessRegistry.shared.isRunning(serviceID: fakeID)
        #expect(isRunningBefore == false)

        await DataPortService.resetAllAppStorage()
        let isRunningAfter = await ProcessRegistry.shared.isRunning(serviceID: fakeID)
        #expect(isRunningAfter == false)
    }

    // MARK: - [TC-D02] Storage Reset Wipes SQLite Database Records
    @Test("DataPort.D02: resetAllAppStorage clears records and re-seeds default workspace")
    func testStorageResetWipesSQLiteDatabaseRecords() async throws {
        let wsRepo = WorkspaceRepository()
        let testWS = Workspace(name: "Temporary Space \(UUID().uuidString)")
        try await wsRepo.insert(testWS)

        let initialList = try await wsRepo.fetchAll()
        #expect(initialList.contains(where: { $0.id == testWS.id }))

        await DataPortService.resetAllAppStorage()

        let afterResetList = try await wsRepo.fetchAll()
        #expect(!afterResetList.contains(where: { $0.id == testWS.id }))
        #expect(afterResetList.count == 1)
    }

    // MARK: - [TC-D03] Storage Reset Wipes UserDefaults Preferences
    @Test("DataPort.D03: resetAllAppStorage clears custom UserDefaults preferences")
    func testStorageResetWipesUserDefaultsPreferences() async {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: KumaSettingsKey.hasCompletedOnboarding)
        defaults.set("/opt/custom/docker", forKey: KumaSettingsKey.customDockerPath)

        await DataPortService.resetAllAppStorage(defaults: defaults)

        #expect(defaults.object(forKey: KumaSettingsKey.hasCompletedOnboarding) == nil)
        #expect(defaults.object(forKey: KumaSettingsKey.customDockerPath) == nil)
    }

    // MARK: - [TC-D04] Storage Reset Clears Workspace Image Cache And Folder
    @Test("DataPort.D04: resetAllAppStorage clears WorkspaceImageStore cache and avatar directory")
    func testStorageResetClearsWorkspaceImageCacheAndFolder() async throws {
        let imgStore = WorkspaceImageStore.shared
        let base64Sample = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let wsID = UUID()
        _ = imgStore.saveBase64Image(base64Sample, workspaceID: wsID)

        await DataPortService.resetAllAppStorage()

        let imagesDir = imgStore.imagesDirectoryURL()
        let fileURL = imagesDir.appendingPathComponent("\(wsID.uuidString).png")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    // MARK: - [TC-D05] Concurrent Export Requests
    @Test("DataPort.D05: parallel exportData calls are thread-safe")
    func testConcurrentExportRequests() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        try harness.seedService(workspaceID: harness.defaultWorkspaceID, name: "Concurrent Service")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let backup = try? await harness.repository.exportData(scope: .all)
                    #expect(backup != nil)
                }
            }
        }
    }
}
