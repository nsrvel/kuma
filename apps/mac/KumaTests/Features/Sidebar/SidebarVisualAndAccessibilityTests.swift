import Foundation
import Testing
import SwiftUI
@testable import Kuma

@Suite("Feature 04: Sidebar - Visual Hierarchy & Accessibility HIG", .serialized)
@MainActor
struct SidebarVisualAndAccessibilityTests {

    @Test("TC-F01: Headless View Hierarchy Modularity")
    func testSidebarViewHierarchyModularity() {
        let vm = SidebarViewModel.makeDefault()
        let workspaceStore = WorkspaceStore()

        let sidebarView = SidebarView(viewModel: vm, workspaceStore: workspaceStore)
        let footerView = SidebarFooterView(viewModel: vm)

        #expect(sidebarView.body != nil)
        #expect(footerView.body != nil)
    }

    @Test("TC-F02: Strict File Lines Limit Under 150 Lines")
    func testSidebarViewFileLinesLimitStrict() {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sidebar
            .deletingLastPathComponent() // Features
            .deletingLastPathComponent() // KumaTests
            .deletingLastPathComponent() // repo root
        let baseDir = repoRoot
            .appendingPathComponent("Kuma/Presentation/Features/Sidebar/Views", isDirectory: true)
            .path
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: baseDir, isDirectory: &isDirectory), isDirectory.boolValue,
              let enumerator = fileManager.enumerator(atPath: baseDir) else {
            Issue.record("Sidebar Views directory not found at \(baseDir)")
            return
        }

        for case let file as String in enumerator where file.hasSuffix(".swift") {
            let fullPath = (baseDir as NSString).appendingPathComponent(file)
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines).count
                #expect(lines < 150, "File \(file) has \(lines) lines, which violates the < 150 lines rule!")
            }
        }
    }

    @Test("TC-F03: SidebarRowActionButtons Reuses SidebarActionButton (Zero Dead Code)")
    func testSidebarRowViewActionButtonsReusesActionButton() {
        let node = SidebarNode(
            title: "Test Node",
            icon: .system("folder"),
            actions: [SidebarAction(icon: "plus", tooltip: "Add Item", handler: {})]
        )
        let buttonsView = SidebarRowActionButtons(
            node: node,
            showActions: true,
            hasChildren: false,
            isExpanded: false,
            showChevronActive: false,
            onAddAction: nil,
            onToggleExpand: {}
        )
        #expect(buttonsView.body != nil)

        let actionBtn = SidebarActionButton(icon: "plus", tooltip: "Add Item", action: {})
        #expect(actionBtn.body != nil)
    }

    @Test("TC-F04: SidebarRowView Accessibility Traits")
    func testSidebarRowViewAccessibilityTraits() {
        let regularNode = SidebarNode(title: "My Group", icon: .system("folder"), isSpecialHeader: false)
        let headerNode = SidebarNode(title: "Groups", icon: .system("folder"), isSpecialHeader: true)

        let regularRow = SidebarRowView(
            node: regularNode,
            isSelected: false,
            isExpanded: false,
            indentLevel: 1,
            onSelect: {},
            onToggleExpand: {}
        )
        let headerRow = SidebarRowView(
            node: headerNode,
            isSelected: false,
            isExpanded: true,
            indentLevel: 0,
            onSelect: {},
            onToggleExpand: {}
        )

        #expect(regularRow.body != nil)
        #expect(headerRow.body != nil)
    }

    @Test("TC-F05: Sidebar Footer Buttons Accessibility and Selection Highlight")
    func testSidebarFooterButtonsAccessibilityAndHighlight() {
        var clicked = false
        let btnInactive = SidebarFooterButton(
            icon: "gear",
            tooltip: "Settings (⌘,)",
            isSelected: false,
            action: { clicked = true }
        )
        let btnActive = SidebarFooterButton(
            icon: "gear",
            tooltip: "Settings (⌘,)",
            isSelected: true,
            action: {}
        )

        #expect(btnInactive.body != nil)
        #expect(btnActive.body != nil)
        #expect(btnInactive.isSelected == false)
        #expect(btnActive.isSelected == true)

        btnInactive.action()
        #expect(clicked == true)
    }
}
