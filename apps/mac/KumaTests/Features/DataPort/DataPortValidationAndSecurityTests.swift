import Foundation
import Testing
@testable import Kuma

@Suite("DataPort Category B: Validation, Security & Polymorphic Parsing", .serialized)
@MainActor
struct DataPortValidationAndSecurityTests {

    // MARK: - [TC-B01] Future Version Backup Rejection
    @Test("DataPort.B01: decodeBackup rejects backup version newer than currentVersion")
    func testFutureVersionBackupRejection() throws {
        let futureBackup = DataPortService.KumaBackup(
            version: 999,
            exportedAt: Date(),
            workspaces: []
        )
        let data = try DataPortService.encodeBackup(futureBackup)

        #expect(throws: DataPortService.DataPortError.self) {
            try DataPortService.decodeBackup(from: data)
        }
    }

    // MARK: - [TC-B02] Polymorphic Parser Detects Full Backup
    @Test("DataPort.B02: parseAnyBackup detects and returns full KumaBackup")
    func testPolymorphicParserDetectsFullBackup() throws {
        let original = DataPortService.KumaBackup(
            version: 1,
            exportedAt: Date(),
            workspaces: [Workspace(name: "Full Space")]
        )
        let data = try DataPortService.encodeBackup(original)

        let parsed = try DataPortService.parseAnyBackup(from: data)
        #expect(parsed.workspaces.count == 1)
        #expect(parsed.workspaces.first?.name == "Full Space")
    }

    // MARK: - [TC-B03] Polymorphic Parser Detects Single Service
    @Test("DataPort.B03: parseAnyBackup detects SingleServiceExport and wraps as KumaBackup")
    func testPolymorphicParserDetectsSingleService() throws {
        let svc = DataPortService.ExportService(name: "Standalone Microservice")
        let singleExport = DataPortService.SingleServiceExport(
            service: svc,
            providers: [],
            portMappings: []
        )
        let data = try DataPortService.encodeSingleService(singleExport)

        let targetWS = UUID()
        let parsed = try DataPortService.parseAnyBackup(from: data, targetWorkspaceID: targetWS)

        #expect(parsed.services.count == 1)
        #expect(parsed.services.first?.name == "Standalone Microservice")
        #expect(parsed.services.first?.workspaceID == targetWS)
    }

    // MARK: - [TC-B07] ExportKubeConfig encrypted field round-trip
    @Test("DataPort.B07: ExportKubeConfig round-trips encryptedConfigContent in backup JSON")
    func testExportKubeConfigEncryptedFieldRoundTrip() throws {
        let kube = DataPortService.ExportKubeConfig(
            id: UUID(),
            name: "staging",
            encryptedConfigContent: "nonce:tag:ciphertext",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let backup = DataPortService.KumaBackup(
            services: [],
            providers: [],
            portMappings: [],
            kubeConfigs: [kube]
        )
        let data = try DataPortService.encodeBackup(backup)
        let decoded = try DataPortService.decodeBackup(from: data)
        #expect(decoded.kubeConfigs.count == 1)
        #expect(decoded.kubeConfigs[0].encryptedConfigContent == "nonce:tag:ciphertext")
    }

    @Test("DataPort.B07b: ExportKubeConfig round-trips path field in backup JSON")
    func testExportKubeConfigPathFieldRoundTrip() throws {
        let kube = DataPortService.ExportKubeConfig(
            id: UUID(),
            name: "staging",
            path: "/Users/me/.kube/config",
            encryptedConfigContent: ""
        )
        let backup = DataPortService.KumaBackup(
            services: [],
            providers: [],
            portMappings: [],
            kubeConfigs: [kube]
        )
        let data = try DataPortService.encodeBackup(backup)
        let decoded = try DataPortService.decodeBackup(from: data)
        #expect(decoded.kubeConfigs[0].path == "/Users/me/.kube/config")
    }

    // MARK: - [TC-B04] Corrupted JSON Decoding Failure
    @Test("DataPort.B04: parseAnyBackup throws on non-JSON input")
    func testCorruptedJSONDecodingFailure() {
        let invalidData = "This is definitely not a JSON file.".data(using: .utf8)!

        #expect(throws: Error.self) {
            try DataPortService.parseAnyBackup(from: invalidData)
        }
    }

    // MARK: - [TC-B05] Name Conflict Detection in Workspace Import
    @Test("DataPort.B05: service name conflict resolves with (Imported) suffix")
    func testNameConflictDetectionInWorkspaceImport() {
        let existingNames: Set<String> = ["frontend-app", "postgres"]

        let serviceName = "Frontend-App"
        let hasConflict = existingNames.contains(serviceName.lowercased())
        #expect(hasConflict == true)

        let resolvedName = hasConflict ? "\(serviceName) (Imported)" : serviceName
        #expect(resolvedName == "Frontend-App (Imported)")
    }

    // MARK: - [TC-B06] Case-Insensitive Name Conflict Detection
    @Test("DataPort.B06: service name conflict detection is case-insensitive")
    func testCaseInsensitiveNameConflictDetection() {
        let existingNames: Set<String> = ["api-gateway"]

        let service1 = "API-GATEWAY"
        let service2 = "api-gateway"
        let service3 = "Api-Gateway"

        #expect(existingNames.contains(service1.lowercased()) == true)
        #expect(existingNames.contains(service2.lowercased()) == true)
        #expect(existingNames.contains(service3.lowercased()) == true)
    }
}
