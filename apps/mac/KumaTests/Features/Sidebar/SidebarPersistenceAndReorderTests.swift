import Foundation
import Testing
@testable import Kuma

@Suite("Feature 04: Sidebar - Persistence & Reordering", .serialized)
@MainActor
struct SidebarPersistenceAndReorderTests {

    @Test("TC-C01: Add Group Optimistic In-Memory & SQLite Persistence")
    func testAddGroupOptimisticAndPersisted() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        vm.addGroup(name: "Microservices", workspaceID: harness.workspaceID)
        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.name == "Microservices")
        #expect(vm.selectedID == vm.groups.first?.id)
        #expect(vm.editingGroupID == vm.groups.first?.id)

        // Wait for background SQLite task
        try await Task.sleep(nanoseconds: 50_000_000)
        let dbGroups = try await harness.repository.fetchAll(workspaceID: harness.workspaceID)
        #expect(dbGroups.count == 1)
        #expect(dbGroups.first?.name == "Microservices")
    }

    @Test("TC-C02: Rename Group Updates SQLite Record")
    func testRenameGroupUpdatesDatabaseRecord() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        vm.addGroup(name: "Old Group", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id
        try await Task.sleep(nanoseconds: 50_000_000)

        vm.renameGroup(id: groupID, newName: "New Group")
        #expect(vm.groups.first?.name == "New Group")
        #expect(vm.editingGroupID == nil)

        try await Task.sleep(nanoseconds: 50_000_000)
        let dbGroups = try await harness.repository.fetchAll(workspaceID: harness.workspaceID)
        #expect(dbGroups.first?.name == "New Group")
    }

    @Test("TC-C03: Delete Group Removes SQLite Record")
    func testDeleteGroupRemovesDatabaseRecord() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        vm.addGroup(name: "To Delete", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id
        try await Task.sleep(nanoseconds: 50_000_000)

        vm.deleteGroup(id: groupID)
        #expect(vm.groups.isEmpty)
        #expect(vm.selectedID == UUID.stable("all-services"))

        try await Task.sleep(nanoseconds: 50_000_000)
        let dbGroups = try await harness.repository.fetchAll(workspaceID: harness.workspaceID)
        #expect(dbGroups.isEmpty)
    }

    @Test("TC-C04: Delete Group Preserves Workspace Services")
    func testDeleteGroupPreservesWorkspaceServices() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        let groupID = UUID()
        let group = ServiceGroup(id: groupID, name: "Database Nodes", workspaceID: harness.workspaceID, sortOrder: 0)
        try await harness.repository.insert(group)

        try harness.seedService(id: UUID(), name: "MySQL Service", groupID: groupID)
        try harness.seedService(id: UUID(), name: "Redis Cache", groupID: groupID)
        #expect(try harness.fetchServiceCount() == 2)

        // Delete group
        try await harness.repository.delete(id: groupID)

        // Services must still exist in SQLite
        #expect(try harness.fetchServiceCount() == 2)
    }

    @Test("TC-C05: Workspace-Scoped Groups Isolation")
    func testWorkspaceScopedGroupsIsolation() async throws {
        let harness = SidebarTestHarness()
        let otherWorkspaceID = UUID()
        try harness.seedWorkspace(id: otherWorkspaceID, name: "Other Space")

        let g1 = ServiceGroup(name: "WS1 Group", workspaceID: harness.workspaceID, sortOrder: 0)
        let g2 = ServiceGroup(name: "WS2 Group", workspaceID: otherWorkspaceID, sortOrder: 0)

        try await harness.repository.insert(g1)
        try await harness.repository.insert(g2)

        let ws1Groups = try await harness.repository.fetchAll(workspaceID: harness.workspaceID)
        let ws2Groups = try await harness.repository.fetchAll(workspaceID: otherWorkspaceID)

        #expect(ws1Groups.count == 1)
        #expect(ws1Groups.first?.name == "WS1 Group")

        #expect(ws2Groups.count == 1)
        #expect(ws2Groups.first?.name == "WS2 Group")
    }

    @Test("TC-C06: Move Groups Updates Sort Orders Batch")
    func testMoveGroupsUpdatesSortOrdersBatch() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        vm.addGroup(name: "G0", workspaceID: harness.workspaceID)
        vm.addGroup(name: "G1", workspaceID: harness.workspaceID)
        vm.addGroup(name: "G2", workspaceID: harness.workspaceID)
        try await Task.sleep(nanoseconds: 80_000_000)

        let id0 = vm.groups[0].id
        let id2 = vm.groups[2].id

        // Reorder index 0 down to after index 2
        vm.reorderGroup(draggedID: id0, targetID: id2)

        #expect(vm.groups[0].id != id0)
        #expect(vm.groups.map(\.sortOrder) == [0, 1, 2])

        try await Task.sleep(nanoseconds: 80_000_000)
        let dbGroups = try await harness.repository.fetchAll(workspaceID: harness.workspaceID)
        #expect(dbGroups.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("TC-C07: Concurrent Group Creations")
    func testConcurrentGroupCreations() async throws {
        let harness = SidebarTestHarness()
        let repo = harness.repository
        let wsID = harness.workspaceID

        await withTaskGroup(of: Void.self) { group in
            for i in 1...5 {
                group.addTask {
                    let newGroup = ServiceGroup(name: "Concurrent Group \(i)", workspaceID: wsID, sortOrder: i)
                    try? await repo.insert(newGroup)
                }
            }
        }

        let dbGroups = try await harness.repository.fetchAll(workspaceID: wsID)
        #expect(dbGroups.count == 5)
    }

    @Test("TC-C08: Concurrent Read and Reorder Transactions")
    func testConcurrentReadAndReorderTransactions() async throws {
        let harness = SidebarTestHarness()
        let repo = harness.repository
        let wsID = harness.workspaceID

        for i in 0..<4 {
            let g = ServiceGroup(name: "Group \(i)", workspaceID: wsID, sortOrder: i)
            try await repo.insert(g)
        }

        let groups = try await repo.fetchAll(workspaceID: wsID)
        let orders = groups.reversed().enumerated().map { (index, group) in
            (id: group.id, sortOrder: index)
        }

        // Concurrently run read and updateSortOrders
        async let writeTask: () = repo.updateSortOrders(orders)
        async let readTask: [ServiceGroup] = repo.fetchAll(workspaceID: wsID)

        _ = try await (writeTask, readTask)
        let finalGroups = try await repo.fetchAll(workspaceID: wsID)
        #expect(finalGroups.count == 4)
    }
}
