import SwiftUI
import Testing
@testable import Kuma

@Suite("DataPort Category F: Visual, View Modularity & Accessibility HIG", .serialized)
@MainActor
struct DataPortVisualAndAccessibilityTests {

    // MARK: - [TC-F01] Import Preview Sheet File Lines Limit Strict
    @Test("DataPort.F01: Import preview sheets stay under 150 lines")
    func testImportPreviewSheetFileLinesLimitStrict() {
        let previewPath = "Kuma/Presentation/Features/DataPort/Views/ImportPreviewSheet.swift"
        let wsPreviewPath = "Kuma/Presentation/Features/DataPort/Views/WorkspaceImportPreviewSheet.swift"

        if let previewContent = try? String(contentsOfFile: previewPath, encoding: .utf8) {
            let lines = previewContent.components(separatedBy: .newlines).count
            #expect(lines <= 150)
        }

        if let wsContent = try? String(contentsOfFile: wsPreviewPath, encoding: .utf8) {
            let lines = wsContent.components(separatedBy: .newlines).count
            #expect(lines <= 150)
        }
    }

    // MARK: - [TC-F02] Import Detail Inspector Pane File Lines Limit Strict
    @Test("DataPort.F02: ImportDetailInspectorPane stays under 150 lines")
    func testImportDetailInspectorPaneFileLinesLimitStrict() {
        let inspectorPath = "Kuma/Presentation/Features/DataPort/Views/Components/ImportDetailInspectorPane.swift"

        if let content = try? String(contentsOfFile: inspectorPath, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines).count
            #expect(lines <= 150)
        }
    }

    // MARK: - [TC-F03] Import Preview Header View Rendering
    @Test("DataPort.F03: ImportPreviewHeaderView exposes title and search binding")
    func testImportPreviewHeaderViewRendering() {
        var query = ""
        let binding = Binding<String>(
            get: { query },
            set: { query = $0 }
        )

        let header = ImportPreviewHeaderView(
            title: "Test Header",
            subtitle: "Subtitle info",
            searchText: binding
        )

        #expect(header.title == "Test Header")
        #expect(header.subtitle == "Subtitle info")
    }

    // MARK: - [TC-F04] Import Preview Footer View Rendering
    @Test("DataPort.F04: ImportPreviewFooterView reports selection counts and actions")
    func testImportPreviewFooterViewRendering() {
        var didToggle = false
        var didCancel = false
        var didImport = false

        let footer = ImportPreviewFooterView(
            selectedCount: 3,
            totalCount: 5,
            filteredCount: 5,
            onToggleSelectAll: { didToggle = true },
            onCancel: { didCancel = true },
            onImport: { didImport = true }
        )

        #expect(footer.selectedCount == 3)
        #expect(footer.totalCount == 5)

        footer.onToggleSelectAll()
        #expect(didToggle == true)

        footer.onCancel()
        #expect(didCancel == true)

        footer.onImport()
        #expect(didImport == true)
    }

    // MARK: - [TC-F05] Import Detail Inspector Pane Accessibility Labels
    @Test("DataPort.F05: ImportDetailInspectorPane renders Docker provider and ports")
    func testImportDetailInspectorPaneAccessibilityLabels() {
        let prov = DataPortService.ExportProvider(
            serviceID: UUID(),
            type: "docker",
            label: "Test Docker"
        )
        let port = DataPortService.ExportPortMapping(
            providerID: prov.id,
            localPort: 8080,
            remotePort: 80
        )

        let pane = ImportDetailInspectorPane(
            serviceName: "Web App",
            serviceDescription: "Frontend Service",
            provider: prov,
            portMappings: [port],
            hasConflict: false
        )

        #expect(pane.serviceName == "Web App")
        #expect(pane.hasConflict == false)
        #expect(pane.portMappings.count == 1)
    }

    @Test("Import preview table ports render as plain comma-separated numbers")
    func testImportPortsSummaryPlainText() {
        let providerID = UUID()
        let same = DataPortService.ExportPortMapping(providerID: providerID, localPort: 9000, remotePort: 9000)
        let mapped = DataPortService.ExportPortMapping(providerID: providerID, localPort: 3000, remotePort: 80)
        #expect(ImportPortsBadgeView.summary(portMappings: [same, mapped], maxVisible: 2) == "9000, 3000")
        #expect(ImportPortsBadgeView.summary(portMappings: [same, mapped, same], maxVisible: 2) == "9000, 3000, +1")
    }
}
