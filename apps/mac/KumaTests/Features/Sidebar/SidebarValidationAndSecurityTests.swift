import Foundation
import GRDB
import Testing
@testable import Kuma

@Suite("Feature 04: Sidebar - Input Validation & Security", .serialized)
@MainActor
struct SidebarValidationAndSecurityTests {

    @Test("TC-B01: Group Name Whitespace Trimming")
    func testGroupNameTrimmingWhitespaces() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "Initial", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id

        vm.renameGroup(id: groupID, newName: "   Production Cluster   ")
        #expect(vm.groups.first?.name == "Production Cluster")
    }

    @Test("TC-B02: Empty Group Name Fallback to Untitled")
    func testEmptyGroupNameFallbackToUntitled() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "Test", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id

        vm.renameGroup(id: groupID, newName: "    ")
        #expect(vm.groups.first?.name == "Untitled Group")

        vm.renameGroup(id: groupID, newName: "")
        #expect(vm.groups.first?.name == "Untitled Group")
    }

    @Test("TC-B03: Group Name With Special Characters and Emoji")
    func testGroupNameWithSpecialCharactersAndEmoji() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        let complexName = "⚡ Cloudflare Tunnels (Staging/v2)"
        vm.addGroup(name: complexName, workspaceID: harness.workspaceID)
        #expect(vm.groups.first?.name == complexName)
    }

    @Test("TC-B04: Group Name Boundary Length Handling")
    func testGroupNameBoundaryLength() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        let longName = String(repeating: "A", count: 300)
        vm.addGroup(name: longName, workspaceID: harness.workspaceID)
        #expect(vm.groups.first?.name.count == 300)
    }

    @Test("TC-B05: Drag-and-Drop Payload UUID Validation")
    func testDragDropPayloadUUIDValidation() {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "Group 1", workspaceID: harness.workspaceID)
        vm.addGroup(name: "Group 2", workspaceID: harness.workspaceID)

        let initialOrder = vm.groups.map(\.id)

        // Invalid non-UUID payload simulation
        let malformedString = "not-a-valid-uuid"
        let malformedUUID = UUID(uuidString: malformedString)
        #expect(malformedUUID == nil)

        // Same source and target ID should be a no-op
        let targetID = initialOrder.first!
        vm.reorderGroup(draggedID: targetID, targetID: targetID)
        #expect(vm.groups.map(\.id) == initialOrder)
    }

    @Test("TC-B06: Group Membership Join Table Integrity")
    func testGroupMembershipJoinTableIntegrity() throws {
        let harness = SidebarTestHarness()
        let groupID = UUID()
        let group = ServiceGroup(id: groupID, name: "Database Nodes", workspaceID: harness.workspaceID, sortOrder: 0)
        
        try harness.databaseQueue.write { db in
            try group.insert(db)
        }

        let serviceID = UUID()
        try harness.seedService(id: serviceID, name: "PostgreSQL Primary", groupID: groupID)

        // Verify query on join table
        let count = try harness.databaseQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM service_group_membership WHERE serviceID = ? AND groupID = ?", arguments: [serviceID.uuidString, groupID.uuidString])
        }
        #expect(count == 1)
    }
}
