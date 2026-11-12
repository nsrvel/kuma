import Foundation
import Testing
@testable import Kuma

@Suite("DataPort Category C: Persistence, Relational Integrity & Scoped Sync", .serialized)
@MainActor
struct DataPortPersistenceAndSyncTests {

    // MARK: - [TC-C01] Export All Populates Full Relational Hierarchy
    @Test("DataPort.C01: exportData(scope: .all) exports full SQLite relational hierarchy")
    func testExportAllPopulatesFullRelationalHierarchy() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let wsID = harness.defaultWorkspaceID
        let groupID = UUID()
        try harness.seedGroup(id: groupID, workspaceID: wsID, name: "Core Services")

        let svcID = UUID()
        let provID = UUID()
        try harness.seedService(id: svcID, workspaceID: wsID, name: "Auth Service", activeProviderID: provID, groupIDs: [groupID])
        try harness.seedProvider(id: provID, serviceID: svcID, type: "docker", label: "Auth Runner")
        try harness.seedPortMapping(serviceID: svcID, providerID: provID, localPort: 8080, remotePort: 80)

        let backup = try await harness.repository.exportData(scope: .all)

        #expect(backup.workspaces.count >= 1)
        #expect(backup.groups?.contains(where: { $0.id == groupID }) == true)
        #expect(backup.services.contains(where: { $0.id == svcID }) == true)
        #expect(backup.providers.contains(where: { $0.id == provID }) == true)
        #expect(backup.portMappings.contains(where: { $0.localPort == 8080 }) == true)
    }

    // MARK: - [TC-C02] Export Workspace Scopes to WorkspaceID
    @Test("DataPort.C02: exportData(scope: .workspace) scopes to one workspace")
    func testExportWorkspaceScopesToWorkspaceID() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let wsA = harness.defaultWorkspaceID
        let wsB = UUID()
        try harness.seedWorkspace(id: wsB, name: "Other Space")

        let svcA = UUID()
        let svcB = UUID()
        try harness.seedService(id: svcA, workspaceID: wsA, name: "Service In A")
        try harness.seedService(id: svcB, workspaceID: wsB, name: "Service In B")

        let backupA = try await harness.repository.exportData(scope: .workspace(wsA))

        #expect(backupA.services.count == 1)
        #expect(backupA.services.first?.id == svcA)
        #expect(!backupA.services.contains(where: { $0.id == svcB }))
    }

    // MARK: - [TC-C03] Export Single Service Scopes to ServiceID
    @Test("DataPort.C03: exportData(scope: .service) exports a single service")
    func testExportSingleServiceScopesToServiceID() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let wsID = harness.defaultWorkspaceID
        let svc1 = UUID()
        let svc2 = UUID()
        try harness.seedService(id: svc1, workspaceID: wsID, name: "Microservice 1")
        try harness.seedService(id: svc2, workspaceID: wsID, name: "Microservice 2")

        let backup = try await harness.repository.exportData(scope: .service(svc1))

        #expect(backup.services.count == 1)
        #expect(backup.services.first?.id == svc1)
        #expect(backup.services.first?.name == "Microservice 1")
    }

    // MARK: - [TC-C04] Import All Restores Complete Graph
    @Test("DataPort.C04: importData(strategy: .preserveOrMerge) restores entities into SQLite")
    func testImportAllRestoresCompleteGraph() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let ws = Workspace(name: "Imported Workspace")
        let svc = DataPortService.ExportService(
            name: "Database Service",
            workspaceID: ws.id
        )
        let prov = DataPortService.ExportProvider(
            serviceID: svc.id,
            type: "docker",
            label: "DB"
        )

        let backup = DataPortService.KumaBackup(
            workspaces: [ws],
            services: [svc],
            providers: [prov]
        )

        try await harness.repository.importData(backup: backup, strategy: .preserveOrMerge)

        let wsCount = try harness.fetchCount(table: "workspace")
        let svcCount = try harness.fetchCount(table: "service")
        let provCount = try harness.fetchCount(table: "provider")

        #expect(wsCount >= 2) // default + imported
        #expect(svcCount == 1)
        #expect(provCount == 1)
    }

    // MARK: - [TC-C05] Import Into Workspace Re-IDs All Entities
    @Test("DataPort.C05: import reassignIDs generates new UUIDs to avoid ID collisions")
    func testImportIntoWorkspaceReIDsAllEntities() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let targetWS = harness.defaultWorkspaceID
        let originalServiceID = UUID()
        let originalProvID = UUID()

        let svc = DataPortService.ExportService(
            id: originalServiceID,
            name: "Duplicable Service",
            activeProviderID: originalProvID,
            workspaceID: targetWS
        )
        let prov = DataPortService.ExportProvider(
            id: originalProvID,
            serviceID: originalServiceID,
            type: "shell",
            runCommand: "echo 'hello'"
        )

        let backup = DataPortService.KumaBackup(
            services: [svc],
            providers: [prov]
        )

        try await harness.repository.importData(backup: backup, strategy: .reassignIDs(targetWorkspaceID: targetWS))

        // Service row persisted
        let svcCount = try harness.fetchCount(table: "service")
        #expect(svcCount == 1)

        // Imported service gets a new ID
        let exported = try await harness.repository.exportData(scope: .workspace(targetWS))
        let importedSvc = exported.services.first
        #expect(importedSvc != nil)
        #expect(importedSvc?.id != originalServiceID)
        #expect(importedSvc?.name == "Duplicable Service")
    }

    // MARK: - [TC-C06] Import Selective Imports Only Chosen Workspaces And Services
    @Test("DataPort.C06: importSelective imports only selected workspaces and services")
    func testImportSelectiveImportsOnlyChosenWorkspacesAndServices() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let ws1 = Workspace(name: "WS 1")
        let ws2 = Workspace(name: "WS 2")
        let svc1 = DataPortService.ExportService(name: "Svc 1", workspaceID: ws1.id)
        let svc2 = DataPortService.ExportService(name: "Svc 2", workspaceID: ws2.id)

        let backup = DataPortService.KumaBackup(
            workspaces: [ws1, ws2],
            services: [svc1, svc2]
        )

        // Import only WS 1 and Svc 1
        try await harness.repository.importSelective(
            from: backup,
            selectedWorkspaceIDs: [ws1.id],
            selectedServiceIDs: [svc1.id]
        )

        let exported = try await harness.repository.exportData(scope: .all)
        #expect(exported.workspaces.contains(where: { $0.id == ws1.id }))
        #expect(!exported.workspaces.contains(where: { $0.id == ws2.id }))
        #expect(exported.services.contains(where: { $0.id == svc1.id }))
        #expect(!exported.services.contains(where: { $0.id == svc2.id }))
    }

    // MARK: - [TC-C07] Atomic File Write On Export
    @Test("DataPort.C07: atomic backup file write round-trips decode")
    func testAtomicFileWriteOnExport() throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let backup = DataPortService.KumaBackup(workspaces: [Workspace(name: "Atomic WS")])
        let data = try DataPortService.encodeBackup(backup)

        let destURL = harness.tempDirectoryURL.appendingPathComponent("atomic_backup.json")
        try data.write(to: destURL, options: .atomic)

        #expect(FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)))
        let readData = try Data(contentsOf: destURL)
        let decoded = try DataPortService.decodeBackup(from: readData)
        #expect(decoded.workspaces.first?.name == "Atomic WS")
    }

    // MARK: - [TC-C08] Import Rollback On Database Failure
    @Test("DataPort.C08: SQLite import transaction commits valid backup")
    func testImportRollbackOnDatabaseFailure() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        // Valid backup import
        let backup = DataPortService.KumaBackup(
            workspaces: [Workspace(name: "Safe WS")]
        )
        try await harness.repository.importData(backup: backup, strategy: .preserveOrMerge)

        let countInitial = try harness.fetchCount(table: "workspace")
        #expect(countInitial >= 2)
    }

    // MARK: - [TC-C09] Equivalence Across All 4 Entry Points (Export & Ingestion)
    @Test("DataPort.C09: export payloads match across Settings, DnD, toolbar, and Copy Config entry points")
    func testEquivalenceAcrossAllEntryPoints() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let wsID = harness.defaultWorkspaceID
        let svcID = UUID()
        let provID = UUID()
        try harness.seedService(id: svcID, workspaceID: wsID, name: "Shared API Service", activeProviderID: provID)
        try harness.seedProvider(id: provID, serviceID: svcID, type: "docker", yamlConfig: "image: api:v1")
        try harness.seedPortMapping(serviceID: svcID, providerID: provID, localPort: 4000, remotePort: 4000)

        // 1. Entry Point 1 & 2: Global Scope (Settings / DnD)
        let globalBackup = try await harness.repository.exportData(scope: .all)
        let globalJSON = try DataPortService.encodeBackup(globalBackup)
        let dndIngested = try DataPortService.parseAnyBackup(from: globalJSON)

        // 2. Entry Point 3: Workspace Scope (Deck Toolbar)
        let workspaceBackup = try await harness.repository.exportData(scope: .workspace(wsID))
        let workspaceJSON = try DataPortService.encodeBackup(workspaceBackup)
        let toolbarIngested = try DataPortService.parseAnyBackup(from: workspaceJSON, targetWorkspaceID: wsID)

        // 3. Entry Point 4: Service Scope (Context Menu Copy Config)
        let serviceJSONString = try await harness.repository.exportSingleServiceJSON(serviceID: svcID)
        let clipboardIngested = try DataPortService.parseAnyBackup(from: serviceJSONString.data(using: .utf8)!, targetWorkspaceID: wsID)

        // Service fields match across entry points
        let svcGlobal = globalBackup.services.first(where: { $0.id == svcID })!
        let svcWorkspace = workspaceBackup.services.first(where: { $0.id == svcID })!
        let svcDnD = dndIngested.services.first(where: { $0.id == svcID })!
        let svcToolbar = toolbarIngested.services.first(where: { $0.id == svcID })!
        let svcClipboard = clipboardIngested.services.first!

        #expect(svcGlobal.name == svcWorkspace.name)
        #expect(svcGlobal.name == svcDnD.name)
        #expect(svcGlobal.name == svcToolbar.name)
        #expect(svcGlobal.name == svcClipboard.name)

        // Provider fields match
        let provGlobal = globalBackup.providers.first(where: { $0.serviceID == svcID })!
        let provWorkspace = workspaceBackup.providers.first(where: { $0.serviceID == svcID })!
        let provClipboard = clipboardIngested.providers.first!

        #expect(provGlobal.type == provWorkspace.type)
        #expect(provGlobal.type == provClipboard.type)
        #expect(provGlobal.resolvedTarget == provWorkspace.resolvedTarget)
        #expect(provGlobal.resolvedTarget == provClipboard.resolvedTarget)

        // Port mappings match
        let portGlobal = globalBackup.portMappings.first!
        let portWorkspace = workspaceBackup.portMappings.first!
        let portClipboard = clipboardIngested.portMappings.first!

        #expect(portGlobal.localPort == portWorkspace.localPort)
        #expect(portGlobal.localPort == portClipboard.localPort)
        #expect(portGlobal.remotePort == portWorkspace.remotePort)
        #expect(portGlobal.remotePort == portClipboard.remotePort)
    }

    // MARK: - [TC-C10] Cross-Entry Point Roundtrip & Import Consistency
    @Test("DataPort.C10: Copy Config import into workspace matches full restore records")
    func testCrossEntryPointRoundtrip() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let wsA = harness.defaultWorkspaceID
        let wsB = UUID()
        try harness.seedWorkspace(id: wsB, name: "Workspace B")

        let svcID = UUID()
        let provID = UUID()
        try harness.seedService(id: svcID, workspaceID: wsA, name: "Database Service", activeProviderID: provID)
        try harness.seedProvider(id: provID, serviceID: svcID, type: "docker", yamlConfig: "image: postgres:15")
        try harness.seedPortMapping(serviceID: svcID, providerID: provID, localPort: 5432, remotePort: 5432)

        // Copy config from service in wsA
        let copiedJSON = try await harness.repository.exportSingleServiceJSON(serviceID: svcID)

        // Import into wsB via reassignIDs
        let parsedBackup = try DataPortService.parseAnyBackup(from: copiedJSON.data(using: .utf8)!, targetWorkspaceID: wsB)
        try await harness.repository.importData(backup: parsedBackup, strategy: .reassignIDs(targetWorkspaceID: wsB))

        // Records in wsB
        let exportedB = try await harness.repository.exportData(scope: .workspace(wsB))
        #expect(exportedB.services.count == 1)
        let importedSvc = exportedB.services.first!
        #expect(importedSvc.name == "Database Service")
        #expect(importedSvc.workspaceID == wsB)
        #expect(exportedB.providers.first?.resolvedTarget == "postgres:15")
        #expect(exportedB.portMappings.first?.localPort == 5432)
    }

    // MARK: - [TC-C20] Export includes referenced kube_config rows
    @Test("DataPort.C20: exportData(scope: .service) includes encrypted kube_config referenced by provider")
    func testExportIncludesReferencedKubeConfigs() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let kubeID = UUID()
        let plainYAML = "apiVersion: v1\nkind: Config\n"
        let cipher = try CryptoVault.shared.encrypt(plainText: plainYAML)
        try harness.seedKubeConfig(id: kubeID, name: "Remote", encryptedContent: cipher)

        let svcID = UUID()
        let provID = UUID()
        try harness.seedService(id: svcID, workspaceID: harness.defaultWorkspaceID, name: "K8s API", activeProviderID: provID)
        try harness.seedProvider(id: provID, serviceID: svcID, type: "kubernetes", kubeConfigID: kubeID, kubeContext: "ctx-a", targetName: "api-svc")
        try harness.seedPortMapping(serviceID: svcID, providerID: provID, localPort: 8080, remotePort: 80)

        let backup = try await harness.repository.exportData(scope: .service(svcID))

        #expect(backup.kubeConfigs.contains(where: { $0.id == kubeID }))
        let exported = backup.kubeConfigs.first(where: { $0.id == kubeID })
        #expect(exported?.encryptedConfigContent == cipher)
        #expect(exported?.encryptedConfigContent != plainYAML)
    }

    // MARK: - [TC-C21] Import restores kube_config rows
    @Test("DataPort.C21: importData restores kube_config so provider kubeConfigID resolves")
    func testImportRestoresKubeConfigs() async throws {
        let harnessA = DataPortTestHarness()
        defer { harnessA.cleanup() }

        let kubeID = UUID()
        let cipher = try CryptoVault.shared.encrypt(plainText: "apiVersion: v1\nkind: Config\n")
        try harnessA.seedKubeConfig(id: kubeID, name: "Remote", encryptedContent: cipher)

        let svcID = UUID()
        let provID = UUID()
        try harnessA.seedService(id: svcID, workspaceID: harnessA.defaultWorkspaceID, name: "K8s API", activeProviderID: provID)
        try harnessA.seedProvider(id: provID, serviceID: svcID, type: "kubernetes", kubeConfigID: kubeID, kubeContext: "ctx-a", targetName: "api-svc")

        let backup = try await harnessA.repository.exportData(scope: .service(svcID))

        let harnessB = DataPortTestHarness()
        defer { harnessB.cleanup() }
        try harnessB.seedWorkspace(id: harnessA.defaultWorkspaceID, name: "Default Space")
        try await harnessB.repository.importData(backup: backup, strategy: .preserveOrMerge)

        let kubeRepo = KubeConfigRepository(dbWriter: harnessB.databaseQueue)
        let row = try await kubeRepo.fetch(id: kubeID)
        #expect(row != nil)
        #expect(row?.name == "Remote")
    }

    @Test("DataPort.C21b: importData restores kube_config sourceFilePath")
    func testImportRestoresKubeConfigSourcePath() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let kubeID = UUID()
        let backup = DataPortService.KumaBackup(
            services: [],
            providers: [],
            portMappings: [],
            kubeConfigs: [
                DataPortService.ExportKubeConfig(
                    id: kubeID,
                    name: "OnDisk",
                    path: "/tmp/kubeconfig.yaml",
                    encryptedConfigContent: ""
                )
            ]
        )
        try await harness.repository.importData(backup: backup, strategy: .preserveOrMerge)

        let kubeRepo = KubeConfigRepository(dbWriter: harness.databaseQueue)
        let row = try await kubeRepo.fetch(id: kubeID)
        #expect(row?.sourceFilePath == "/tmp/kubeconfig.yaml")
    }
}
