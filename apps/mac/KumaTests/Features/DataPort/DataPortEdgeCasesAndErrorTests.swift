import Foundation
import Testing
@testable import Kuma

@Suite("DataPort Category E: Edge Cases, Quirks & Fallback Resolution", .serialized)
@MainActor
struct DataPortEdgeCasesAndErrorTests {

    // MARK: - [TC-E01] Export Non-Existent Single Service Throws 404
    @Test("DataPort.E01: exportData(scope: .service) throws when service is missing")
    func testExportNonExistentSingleServiceThrows404() async {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let fakeID = UUID()
        await #expect(throws: Error.self) {
            try await harness.repository.exportData(scope: .service(fakeID))
        }
    }

    // MARK: - [TC-E02] Import Backup With Null Optional Fields
    @Test("DataPort.E02: import succeeds when groups and workspaceImages are nil")
    func testImportBackupWithNullOptionalFields() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let backup = DataPortService.KumaBackup(
            workspaces: [Workspace(name: "No-Images Workspace")],
            workspaceImages: nil,
            groups: nil,
            services: []
        )

        try await harness.repository.importData(backup: backup, strategy: .preserveOrMerge)
        let count = try harness.fetchCount(table: "workspace")
        #expect(count >= 2)
    }

    // MARK: - [TC-E03] Import Service Without Providers Or Ports
    @Test("DataPort.E03: service without providers or ports imports safely")
    func testImportServiceWithoutProvidersOrPorts() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let ws = Workspace(name: "Standalone Services Space")
        let svc = DataPortService.ExportService(
            name: "Bare Service",
            workspaceID: ws.id
        )

        let backup = DataPortService.KumaBackup(
            workspaces: [ws],
            services: [svc],
            providers: [],
            portMappings: []
        )

        try await harness.repository.importData(backup: backup, strategy: .preserveOrMerge)

        let svcCount = try harness.fetchCount(table: "service")
        #expect(svcCount == 1)
    }

    // MARK: - [TC-E04] Port Mapping ProviderID Resolution Fallback
    @Test("DataPort.E04: port mapping preserves provider relationship on import")
    func testPortMappingProviderIDResolutionFallback() async throws {
        let harness = DataPortTestHarness()
        defer { harness.cleanup() }

        let ws = Workspace(name: "Port Space")
        let svc = DataPortService.ExportService(name: "Web", workspaceID: ws.id)
        let prov = DataPortService.ExportProvider(serviceID: svc.id, type: "docker")
        let port = DataPortService.ExportPortMapping(providerID: prov.id, localPort: 3000, remotePort: 3000)

        let backup = DataPortService.KumaBackup(
            workspaces: [ws],
            services: [svc],
            providers: [prov],
            portMappings: [port]
        )

        try await harness.repository.importData(backup: backup, strategy: .preserveOrMerge)

        let portCount = try harness.fetchCount(table: "portMapping")
        #expect(portCount == 1)
    }

    // MARK: - [TC-E05] Compose Image Extraction From Yaml Config
    @Test("DataPort.E05: resolvedTarget extracts Docker image from image: line in YAML")
    func testComposeImageExtractionFromYamlConfig() {
        let yaml = """
        version: '3.8'
        services:
          web:
            image: "docker.io/library/redis:alpine"
            ports:
              - 6379:6379
        """

        let provider = DataPortService.ExportProvider(
            serviceID: UUID(),
            type: "docker",
            yamlConfig: yaml
        )

        #expect(provider.resolvedTarget == "redis:alpine")
    }

    // MARK: - [TC-E06] Clipboard JSON Paste Verification
    @Test("DataPort.E06: Copy Config payload parses via parseAnyBackup for import")
    func testClipboardJSONPasteVerification() throws {
        let svc = DataPortService.ExportService(name: "Clipboard Service")
        let prov = DataPortService.ExportProvider(serviceID: svc.id, type: "shell", runCommand: "ls -la")
        let singleExport = DataPortService.SingleServiceExport(
            service: svc,
            providers: [prov],
            portMappings: []
        )

        let encodedData = try DataPortService.encodeSingleService(singleExport)
        let jsonString = String(data: encodedData, encoding: .utf8)!

        let targetWS = UUID()
        let parsed = try DataPortService.parseAnyBackup(from: jsonString.data(using: .utf8)!, targetWorkspaceID: targetWS)

        #expect(parsed.services.count == 1)
        #expect(parsed.services.first?.name == "Clipboard Service")
        #expect(parsed.services.first?.workspaceID == targetWS)
        #expect(parsed.providers.first?.runCommand == "ls -la")
    }
}
