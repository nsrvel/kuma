import Foundation
import Testing
@testable import Kuma

@Suite("DataPort Category A: Initial State, Scopes & Wrap Contracts", .serialized)
@MainActor
struct DataPortInitialStateTests {

    // MARK: - [TC-A01] KumaBackup Default Properties
    @Test("DataPort.A01: default KumaBackup initializer produces valid defaults")
    func testKumaBackupDefaultProperties() {
        let backup = DataPortService.KumaBackup()

        #expect(backup.version == DataPortService.currentVersion)
        #expect(backup.workspaces.isEmpty)
        #expect(backup.services.isEmpty)
        #expect(backup.providers.isEmpty)
        #expect(backup.portMappings.isEmpty)
        #expect(backup.kubeConfigs.isEmpty)
        #expect(backup.groups == nil)
        #expect(backup.workspaceImages == nil)
        #expect(backup.exportedAt.timeIntervalSince1970 > 0)
    }

    // MARK: - [TC-A02] KumaBackup Deterministic ID
    @Test("DataPort.A02: KumaBackup id is stable and encodes version, timestamp, and count")
    func testKumaBackupDeterministicID() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let backup = DataPortService.KumaBackup(
            version: 1,
            exportedAt: date,
            workspaces: [Workspace(name: "Alpha"), Workspace(name: "Beta")]
        )

        #expect(backup.id == "1_1700000000.0_2")
    }

    // MARK: - [TC-A03] Backup Date String Formatting
    @Test("DataPort.A03: backupDateString uses yyyy-MM-dd format")
    func testBackupDateStringFormatting() {
        let dateStr = DataPortService.backupDateString
        #expect(dateStr.count == 10)

        let parts = dateStr.components(separatedBy: "-")
        #expect(parts.count == 3)
        #expect(parts[0].count == 4)
        #expect(parts[1].count == 2)
        #expect(parts[2].count == 2)
    }

    // MARK: - [TC-A04] SingleServiceExport Wrap to Backup
    @Test("DataPort.A04: wrapSingleService converts SingleServiceExport into valid KumaBackup")
    func testSingleServiceExportWrapToBackup() {
        let service = DataPortService.ExportService(
            name: "Redis Cache",
            icon: "shippingbox",
            colorHex: "#FF0000"
        )
        let provider = DataPortService.ExportProvider(
            serviceID: service.id,
            type: "docker",
            yamlConfig: "image: redis:alpine"
        )
        let port = DataPortService.ExportPortMapping(
            providerID: provider.id,
            localPort: 6379,
            remotePort: 6379
        )

        let singleExport = DataPortService.SingleServiceExport(
            service: service,
            providers: [provider],
            portMappings: [port]
        )

        let targetWS = UUID()
        let wrappedBackup = DataPortService.wrapSingleService(singleExport, targetWorkspaceID: targetWS)

        #expect(wrappedBackup.services.count == 1)
        #expect(wrappedBackup.services.first?.name == "Redis Cache")
        #expect(wrappedBackup.services.first?.workspaceID == targetWS)
        #expect(wrappedBackup.providers.count == 1)
        #expect(wrappedBackup.portMappings.count == 1)
    }

    // MARK: - [TC-A05] DataPortScope Definition
    @Test("DataPort.A05: DataPortScope satisfies Equatable and Sendable")
    func testDataPortScopeDefinition() {
        let uuid = UUID()
        let scopeAll = DataPortService.DataPortScope.all
        let scopeWS = DataPortService.DataPortScope.workspace(uuid)
        let scopeSvc = DataPortService.DataPortScope.service(uuid)

        #expect(scopeAll == .all)
        #expect(scopeWS == .workspace(uuid))
        #expect(scopeSvc == .service(uuid))
        #expect(scopeWS != scopeAll)
    }

    // MARK: - [TC-A06] ExportProvider Category Mapping
    @Test("DataPort.A06: provider type raw strings map to ProviderCategory")
    func testExportProviderCategoryMapping() {
        let testCases: [(String, ProviderCategory)] = [
            ("docker", .docker),
            ("podman", .podman),
            ("kubernetes", .kubernetes),
            ("kube_port_forward", .kubernetes),
            ("shell", .shell),
            ("ssh", .ssh),
            ("http_check", .httpCheck),
            ("httpCheck", .httpCheck),
            ("tunnel", .tunnel),
            ("process_monitor", .processMonitor),
            ("processMonitor", .processMonitor),
            ("unknown_category", .docker)
        ]

        for (rawType, expectedCategory) in testCases {
            let p = DataPortService.ExportProvider(serviceID: UUID(), type: rawType)
            #expect(p.category == expectedCategory)
        }
    }

    // MARK: - [TC-A07] Screenshot sample backup decodes
    @Test("DataPort.A07: docs sample Kuma-Screenshot-Demo.json decodes as KumaBackup")
    func testScreenshotSampleBackupDecodes() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("docs/samples/Kuma-Screenshot-Demo.json")
        let data = try Data(contentsOf: url)
        let backup = try DataPortService.parseAnyBackup(from: data)
        #expect(backup.version == 1)
        #expect(backup.workspaces.count == 1)
        #expect(backup.services.count == 8)
        #expect(backup.providers.count == 8)
        #expect(Set(backup.providers.map(\.type)).count == 8)
    }
}
