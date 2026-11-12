import Foundation
import Testing
@testable import Kuma

@Suite("Feature 04: Sidebar - Runtime & Notifications", .serialized)
@MainActor
struct SidebarRuntimeAndNotificationTests {

    @Test("TC-D01: Notification Posted On Group Add")
    func testNotificationPostedOnGroupAdd() async {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: .kumaGroupsUpdated,
            object: nil,
            queue: .main
        ) { _ in notificationFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.addGroup(name: "New Group", workspaceID: harness.workspaceID)
        let deadline = Date().addingTimeInterval(1.0)
        while !notificationFired && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(notificationFired == true)
    }

    @Test("TC-D02: Notification Posted On Group Rename")
    func testNotificationPostedOnGroupRename() async {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "G1", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id
        try? await Task.sleep(nanoseconds: 50_000_000)

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: .kumaGroupsUpdated,
            object: nil,
            queue: .main
        ) { notif in
            if notif.object as? UUID == groupID {
                notificationFired = true
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.renameGroup(id: groupID, newName: "Renamed G1")
        let deadline = Date().addingTimeInterval(1.0)
        while !notificationFired && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(notificationFired == true)
    }

    @Test("TC-D03: Notification Posted On Group Delete")
    func testNotificationPostedOnGroupDelete() async {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "To Delete", workspaceID: harness.workspaceID)
        let groupID = vm.groups.first!.id
        try? await Task.sleep(nanoseconds: 50_000_000)

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: .kumaGroupsUpdated,
            object: nil,
            queue: .main
        ) { notif in
            if notif.object as? UUID == groupID {
                notificationFired = true
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.deleteGroup(id: groupID)
        let deadline = Date().addingTimeInterval(1.0)
        while !notificationFired && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(notificationFired == true)
    }

    @Test("TC-D04: Notification Posted On Group Reorder")
    func testNotificationPostedOnGroupReorder() async {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)
        vm.addGroup(name: "G0", workspaceID: harness.workspaceID)
        vm.addGroup(name: "G1", workspaceID: harness.workspaceID)
        for _ in 0..<20 {
            if vm.groups.count >= 2 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        var notificationFired = false
        let token = NotificationCenter.default.addObserver(
            forName: .kumaGroupsUpdated,
            object: nil,
            queue: .main
        ) { _ in notificationFired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        vm.moveGroups(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let deadline = Date().addingTimeInterval(1.0)
        while !notificationFired && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(notificationFired == true)
    }

    @Test("TC-D05: Workspace Switch Triggers Group Reload")
    func testWorkspaceSwitchTriggersReload() async throws {
        let harness = SidebarTestHarness()
        let ws1 = harness.workspaceID
        let ws2 = UUID()
        try harness.seedWorkspace(id: ws2, name: "Workspace 2")

        let g1 = ServiceGroup(name: "Workspace 1 Group", workspaceID: ws1, sortOrder: 0)
        let g2 = ServiceGroup(name: "Workspace 2 Group", workspaceID: ws2, sortOrder: 0)
        try await harness.repository.insert(g1)
        try await harness.repository.insert(g2)

        let vm = SidebarViewModel(groupRepository: harness.repository)
        await vm.loadGroups(workspaceID: ws1)
        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.name == "Workspace 1 Group")

        await vm.loadGroups(workspaceID: ws2)
        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.name == "Workspace 2 Group")
    }

    @Test("TC-D06: Concurrent Reload Deduplication")
    func testConcurrentReloadDeduplication() async throws {
        let harness = SidebarTestHarness()
        let vm = SidebarViewModel(groupRepository: harness.repository)

        let g = ServiceGroup(name: "Dedupe Group", workspaceID: harness.workspaceID, sortOrder: 0)
        try await harness.repository.insert(g)

        // Simultaneous reload calls
        async let r1: () = vm.loadGroups(workspaceID: harness.workspaceID)
        async let r2: () = vm.loadGroups(workspaceID: harness.workspaceID)

        _ = await (r1, r2)
        #expect(vm.groups.count == 1)
        #expect(vm.groups.first?.name == "Dedupe Group")
    }
}
