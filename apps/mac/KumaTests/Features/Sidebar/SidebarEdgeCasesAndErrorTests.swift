import Foundation
import SwiftUI
import Testing
@testable import Kuma

@Suite("Feature 04: Sidebar - Edge Cases & Error Handling", .serialized)
@MainActor
struct SidebarEdgeCasesAndErrorTests {

    @Test("Sidebar.E01: Deleting Active Selected Group Falls Back To All Services")
    func testDeleteActiveSelectedGroupFallsBackToAllServices() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        vm.addGroup(name: "Selected Group", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id
        #expect(vm.selectedID == groupID)

        vm.deleteGroup(id: groupID)
        #expect(vm.selectedID == UUID.stable("all-services"))
    }

    @Test("TC-E02: Keyboard Arrow Down Navigation")
    func testKeyboardArrowDownNavigation() {
        let vm = SidebarViewModel.makeDefault()
        #expect(vm.selectedID == UUID.stable("all-services"))

        vm.handleMove(.down)
        #expect(vm.selectedID == UUID.stable("starred-services"))

        vm.handleMove(.down)
        #expect(vm.selectedID == UUID.stable("groups"))
    }

    @Test("TC-E03: Keyboard Arrow Up Navigation")
    func testKeyboardArrowUpNavigation() {
        let vm = SidebarViewModel.makeDefault()
        vm.selectedID = UUID.stable("groups")

        vm.handleMove(.up)
        #expect(vm.selectedID == UUID.stable("starred-services"))

        vm.handleMove(.up)
        #expect(vm.selectedID == UUID.stable("all-services"))
    }

    @Test("TC-E04: Keyboard Arrow Navigation Boundary Clamps")
    func testKeyboardArrowBoundariesClamp() {
        let vm = SidebarViewModel.makeDefault()
        vm.selectedID = UUID.stable("all-services")

        // Cannot move up past the first element
        vm.handleMove(.up)
        #expect(vm.selectedID == UUID.stable("all-services"))

        // Navigate to last navigable element
        let navigableRows = vm.flattenedRows.filter { $0.isNavigable }
        let lastID = navigableRows.last!.id
        vm.selectedID = lastID

        // Cannot move down past the last element
        vm.handleMove(.down)
        #expect(vm.selectedID == lastID)
    }

    @Test("TC-E05: Keyboard Arrow Left Collapses Group")
    func testKeyboardArrowLeftCollapsesGroup() {
        let vm = SidebarViewModel.makeDefault()
        let groupsID = UUID.stable("groups")
        vm.selectedID = groupsID
        #expect(vm.isExpanded(groupsID))

        vm.handleMove(.left)
        #expect(!vm.isExpanded(groupsID))
    }

    @Test("TC-E06: Keyboard Arrow Right Expands Group")
    func testKeyboardArrowRightExpandsGroup() {
        let vm = SidebarViewModel.makeDefault()
        let groupsID = UUID.stable("groups")
        vm.toggleExpanded(groupsID)
        #expect(!vm.isExpanded(groupsID))

        vm.selectedID = groupsID
        vm.handleMove(.right)
        #expect(vm.isExpanded(groupsID))
    }

    @Test("TC-E07: Move Group Out of Bounds Ignored")
    func testMoveGroupOutOfBoundsIgnored() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "Sole Group", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id

        // Attempting to move up when index is 0
        #expect(vm.canMoveGroupUp(id: groupID) == false)
        vm.moveGroupUp(id: groupID)
        #expect(vm.groups.first?.id == groupID)

        // Attempting to move down when index is count - 1
        #expect(vm.canMoveGroupDown(id: groupID) == false)
        vm.moveGroupDown(id: groupID)
        #expect(vm.groups.first?.id == groupID)
    }

    @Test("TC-E08: Workspace Switch Clears Stale Group Selection")
    func testWorkspaceSwitchClearsStaleGroupSelection() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        let workspaceB = UUID()
        try harness.seedWorkspace(id: workspaceB, name: "Workspace B")

        await vm.loadGroups(workspaceID: harness.workspaceID)
        vm.addGroup(name: "Group A", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id
        #expect(vm.selectedID == groupID)

        await vm.loadGroups(workspaceID: workspaceB)
        #expect(vm.selectedID == UUID.stable("all-services"))
        #expect(vm.groupIDForSelectedRow(vm.selectedID) == nil)

        vm.selectedID = UUID.stable("starred-services")
        await vm.loadGroups(workspaceID: workspaceB)
        #expect(vm.selectedID == UUID.stable("starred-services"))
    }
}
