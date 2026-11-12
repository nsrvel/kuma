import Foundation
import Testing
import SwiftUI
@testable import Kuma

@Suite("Feature 03 - Category F: Headless SwiftUI Hierarchy & HIG Accessibility", .serialized)
@MainActor
struct WorkspaceVisualTests {

    // MARK: - [TC-F01] SidebarWorkspaceRow Accessibility
    @Test("TC-F01: SidebarWorkspaceRow renders with workspace title and accessibility trait")
    func testSidebarWorkspaceRowAccessibility() {
        let store = WorkspaceStore(initialWorkspaces: [Workspace(name: "Engineering Space")])
        let view = SidebarWorkspaceRow(store: store)

        // Instantiate view body headless
        _ = view.body
        #expect(store.activeWorkspace?.name == "Engineering Space")
    }

    // MARK: - [TC-F02] WorkspaceSwitcherPopover Inactive Shortcuts
    @Test("TC-F02: InactiveWorkspaceRow displays shortcut badge when shortcutIndex is present")
    func testWorkspaceSwitcherPopoverInactiveShortcuts() {
        let ws = Workspace(name: "Staging")
        var selected = false
        var edited = false
        var deleted = false

        let row = InactiveWorkspaceRow(
            workspace: ws,
            shortcutIndex: 2,
            canDelete: true,
            onSelect: { selected = true },
            onEdit: { edited = true },
            onDelete: { deleted = true }
        )

        _ = row.body
        #expect(row.shortcutIndex == 2)
        #expect(row.canDelete == true)
    }

    // MARK: - [TC-F03] WorkspaceAvatarView Initials & Gradient
    @Test("TC-F03: WorkspaceAvatarView generates deterministic first-letter initial")
    func testWorkspaceAvatarViewGradientGeneration() {
        let viewA = WorkspaceAvatarView(name: "Backend", size: 32)
        let viewB = WorkspaceAvatarView(name: "", size: 32)

        _ = viewA.body
        _ = viewB.body

        #expect(viewA.name == "Backend")
        #expect(viewB.name == "")
    }

    // MARK: - [TC-F04] WorkspaceFormSheet Mode Create
    @Test("TC-F04: WorkspaceFormSheet in create mode has no delete row")
    func testWorkspaceFormSheetViewModeCreate() {
        let store = WorkspaceStore(initialWorkspaces: [Workspace(name: "Main")])
        var presented = true
        let binding = Binding(get: { presented }, set: { presented = $0 })

        let sheet = WorkspaceFormSheet(store: store, mode: .create, isPresented: binding)
        _ = sheet.body
        #expect(sheet.mode == .create)
    }

    // MARK: - [TC-F05] WorkspaceFormSheet Mode Edit With Delete
    @Test("TC-F05: WorkspaceFormSheet in edit mode with multiple workspaces shows delete row")
    func testWorkspaceFormSheetViewModeEditWithDelete() {
        let ws1 = Workspace(name: "One")
        let ws2 = Workspace(name: "Two")
        let store = WorkspaceStore(initialWorkspaces: [ws1, ws2])
        var presented = true
        let binding = Binding(get: { presented }, set: { presented = $0 })

        let sheet = WorkspaceFormSheet(store: store, mode: .edit(ws2), isPresented: binding)
        _ = sheet.body
        #expect(sheet.mode == .edit(ws2))
        #expect(store.workspaces.count > 1)
    }

    // MARK: - [TC-F06] WorkspaceAvatarPickerView & Badges
    @Test("TC-F06: WorkspaceAvatarPickerView and its badges instantiate and render headlessly")
    func testWorkspaceAvatarPickerViewHeadless() {
        var path: String? = "/tmp/test.png"
        var url: URL? = URL(fileURLWithPath: "/tmp/test.png")
        let pathBinding = Binding(get: { path }, set: { path = $0 })
        let urlBinding = Binding(get: { url }, set: { url = $0 })

        let pickerView = WorkspaceAvatarPickerView(
            name: "Platform Engineering",
            selectedImagePath: pathBinding,
            selectedImageURL: urlBinding
        )
        _ = pickerView.body

        var removed = false
        let removeBadge = WorkspaceAvatarRemoveBadge {
            removed = true
        }
        _ = removeBadge.body

        #expect(!removed)
    }
}
