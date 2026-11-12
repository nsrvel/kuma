import Foundation
import Testing
import SwiftUI
@testable import Kuma

@Suite("Feature 00 - Category G: Global Menu Commands, Notifications & Shortcuts")
@MainActor
struct KumaCommandsTests {

    // MARK: - [TC-G01] Settings Menu Notification
    @Test("TC-G01: kumaOpenSettings notification can be posted and observed")
    func testSettingsMenuNotificationEmission() {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .kumaOpenSettings,
            object: nil,
            queue: .main
        ) { _ in
            received = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.post(name: .kumaOpenSettings, object: nil)
        #expect(received == true)
    }

    // MARK: - [TC-G02] Find Menu Notification
    @Test("TC-G02: kumaFocusSearch notification can be posted and observed")
    func testFindMenuNotificationEmission() {
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .kumaFocusSearch,
            object: nil,
            queue: .main
        ) { _ in
            received = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.post(name: .kumaFocusSearch, object: nil)
        #expect(received == true)
    }

    // MARK: - [TC-G03] Help Menu Onboarding Reset
    @Test("TC-G03: kumaOpenOnboarding notification and coordinator reset work together")
    func testHelpMenuTriggersOnboardingResetAndNotification() {
        let coordinator = AppCoordinator(initialPhase: .mainWorkspace)
        #expect(coordinator.currentPhase == .mainWorkspace)

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .kumaOpenOnboarding,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.resetToOnboarding()
        NotificationCenter.default.post(name: .kumaOpenOnboarding, object: nil)

        #expect(coordinator.currentPhase == .onboarding)
        #expect(notificationReceived == true)
    }

    // MARK: - [TC-G04] Workspaces Menu Dynamic Selection
    @Test("TC-G04: WorkspaceStore selectWorkspace updates current selection safely")
    func testWorkspacesMenuDynamicSelection() {
        let dummyWorkspace = Workspace(name: "Backend Dev", sortOrder: 0)
        let store = WorkspaceStore(initialWorkspaces: [dummyWorkspace])

        store.selectWorkspace(dummyWorkspace)
        #expect(store.selectedWorkspaceId == dummyWorkspace.id)
        #expect(store.activeWorkspace?.name == "Backend Dev")
    }
}
