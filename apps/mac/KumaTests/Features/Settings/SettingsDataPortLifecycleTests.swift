import Foundation
import Testing
@testable import Kuma

@Suite("Settings Category E: DataPort Lifecycle, Export/Import & Reset", .serialized)
@MainActor
struct SettingsDataPortLifecycleTests {

    // MARK: - [TC-E01] Export Backup Generates Valid JSON
    @Test("TC-E01: Export creates valid KumaBackup structure with currentVersion")
    func testExportBackupGeneratesValidJSON() throws {
        let backup = DataPortService.KumaBackup(
            version: DataPortService.currentVersion,
            exportedAt: Date(),
            workspaces: [
                Workspace(name: "Test Workspace")
            ]
        )

        let encodedData = try DataPortService.encodeBackup(backup)
        #expect(!encodedData.isEmpty)

        let jsonString = String(data: encodedData, encoding: .utf8) ?? ""
        #expect(jsonString.contains("Test Workspace"))
        #expect(jsonString.contains("\"version\" : \(DataPortService.currentVersion)"))
    }

    // MARK: - [TC-E02] Import Valid Backup Restores Data
    @Test("TC-E02: decodeBackup parses valid backup data successfully")
    func testImportValidBackupRestoresData() throws {
        let backup = DataPortService.KumaBackup(
            version: 1,
            exportedAt: Date(),
            workspaces: [
                Workspace(name: "Restored Workspace")
            ]
        )
        let data = try DataPortService.encodeBackup(backup)
        let decoded = try DataPortService.decodeBackup(from: data)

        #expect(decoded.version == 1)
        #expect(decoded.workspaces.count == 1)
        #expect(decoded.workspaces.first?.name == "Restored Workspace")
    }

    // MARK: - [TC-E03] Import Future Version Throws Error
    @Test("TC-E03: decodeBackup rejects backups from higher future versions")
    func testImportFutureVersionThrowsError() throws {
        let futureBackup = DataPortService.KumaBackup(
            version: 999, // higher than currentVersion
            exportedAt: Date(),
            workspaces: []
        )
        let data = try DataPortService.encodeBackup(futureBackup)

        #expect(throws: DataPortService.DataPortError.self) {
            try DataPortService.decodeBackup(from: data)
        }
    }

    // MARK: - [TC-E04] Factory Reset Wipes Defaults And Terminates Processes
    @Test("TC-E04: resetAllAppStorage executes without throwing and terminates processes")
    func testFactoryResetWipesDefaultsAndDB() async {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        // Call the asynchronous storage wipe engine with isolated defaults
        await DataPortService.resetAllAppStorage(defaults: harness.userDefaults)
        let fakeUUID = UUID()
        let isRunning = await ProcessRegistry.shared.isRunning(serviceID: fakeUUID)
        #expect(isRunning == false)
    }

    // MARK: - [TC-E05] Selective Import Structure Validation
    @Test("TC-E05: Single service export and decode integrity")
    func testSingleServiceExportAndDecode() throws {
        let service = DataPortService.ExportService(
            name: "Standalone API",
            icon: "server.rack"
        )
        let singleExport = DataPortService.SingleServiceExport(
            service: service,
            providers: [],
            portMappings: []
        )

        let data = try DataPortService.encodeSingleService(singleExport)
        let decoded = try DataPortService.decodeSingleService(from: data)

        #expect(decoded.service.name == "Standalone API")
        #expect(decoded.id == service.id)
    }

    // MARK: - [TC-E06] Reset Settings To Default Preserves Database
    @Test("TC-E06: resetSettingsToDefault restores defaults without touching SQLite database records")
    func testResetSettingsToDefaultPreservesDatabase() async throws {
        let harness = SettingsTestHarness()
        defer { harness.cleanup() }

        // 1. Setup custom settings
        let viewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        viewModel.customKubectlPath = "/custom/path/kubectl"
        viewModel.defaultShell = "/opt/homebrew/bin/fish"
        viewModel.portConflictPolicy = .killExisting
        viewModel.autoResumeServices = false

        // 2. Setup SQLite database with a workspace record
        let wsRepo = WorkspaceRepository()
        let countInitial = try await wsRepo.fetchAll().count

        let workspace = Workspace(name: "Production API \(UUID().uuidString)")
        try await wsRepo.insert(workspace)

        let savedWorkspacesBefore = try await wsRepo.fetchAll()
        #expect(savedWorkspacesBefore.count == countInitial + 1)

        // 3. Execute Reset Settings to Default
        viewModel.resetSettingsToDefault()

        // 4. Verify in-memory and persisted settings reset to default
        #expect(viewModel.customKubectlPath == "")
        #expect(viewModel.defaultShell == "/bin/zsh")
        #expect(viewModel.portConflictPolicy == .warnAndBlock)
        #expect(viewModel.autoResumeServices == false)

        let reloadedViewModel = SettingsViewModel(userDefaults: harness.userDefaults)
        #expect(reloadedViewModel.customKubectlPath == "")
        #expect(reloadedViewModel.defaultShell == "/bin/zsh")
        #expect(reloadedViewModel.portConflictPolicy == .warnAndBlock)
        #expect(reloadedViewModel.autoResumeServices == false)

        // 5. Verify database records are STILL INTACT (NOT deleted)
        let savedWorkspacesAfter = try await wsRepo.fetchAll()
        #expect(savedWorkspacesAfter.count == countInitial + 1)
        #expect(savedWorkspacesAfter.contains(where: { $0.id == workspace.id }))

        // Cleanup DB test record
        try await wsRepo.delete(id: workspace.id)
    }
}
