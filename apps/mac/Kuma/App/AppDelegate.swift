import AppKit
import Foundation
import UserNotifications
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "AppDelegate")

    private enum QuitBehavior: String {
        case ask
        case stopAll
        case quitAnyway
    }

    /// Injected from KumaApp
    var serviceStateStore: ServiceStateStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SingleInstanceGuard.activateExistingInstanceIfRunning() {
            // Defer termination to next turn of runloop so AppKit lifecycle finishes cleanly
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }

        guard !SingleInstanceGuard.isTestingEnvironment else { return }

        UNUserNotificationCenter.current().delegate = self
        Task {
            let status = await SystemNotificationCenter.shared.checkAuthorizationStatus()
            if status == .notDetermined {
                _ = await SystemNotificationCenter.shared.requestAuthorization()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let shouldConfirm = KumaSettingsKey.bool(forKey: KumaSettingsKey.confirmBeforeQuit, defaultValue: true)
        let registryIDs = ProcessRegistry.activeRunningServiceIDs
        let storeIDs = serviceStateStore?.activeServiceIDs ?? []
        let activeIDs = registryIDs.isEmpty ? storeIDs : registryIDs

        // If no services are running or confirmBeforeQuit is turned off, terminate cleanly
        guard shouldConfirm && !activeIDs.isEmpty else {
            snapshotAndTeardown(activeIDs: activeIDs)
            return .terminateNow
        }

        let stored = UserDefaults.standard.string(forKey: KumaSettingsKey.quitBehavior)
        let behavior = QuitBehavior(rawValue: stored ?? "") ?? .ask

        switch behavior {
        case .stopAll:
            snapshotActiveIDs(activeIDs)
            performTeardownAndQuit(sender: sender)
            return .terminateLater

        case .quitAnyway:
            snapshotActiveIDs(activeIDs)
            return .terminateNow

        case .ask:
            break
        }

        NSApp.activate(ignoringOtherApps: true)

        // Show synchronous alert directly on the Main Actor (AppKit guarantees main thread here)
        let alert = NSAlert()
        alert.messageText = "Processes are still running"
        alert.informativeText = "\(activeIDs.count) service(s) are currently running. Stop everything before quitting, or quit anyway?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop All & Quit")
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Remember this choice"

        let response = alert.runModal()
        let remember = alert.suppressionButton?.state == .on

        switch response {
        case .alertFirstButtonReturn: // Stop All & Quit
            if remember {
                UserDefaults.standard.set(QuitBehavior.stopAll.rawValue, forKey: KumaSettingsKey.quitBehavior)
            }
            snapshotActiveIDs(activeIDs)
            performTeardownAndQuit(sender: sender)
            return .terminateLater

        case .alertSecondButtonReturn: // Quit Anyway
            if remember {
                UserDefaults.standard.set(QuitBehavior.quitAnyway.rawValue, forKey: KumaSettingsKey.quitBehavior)
            }
            snapshotActiveIDs(activeIDs)
            return .terminateNow

        default: // Cancel
            return .terminateCancel
        }
    }

    private func performTeardownAndQuit(sender: NSApplication) {
        Task { @MainActor in
            await ExecutionSupervisor.shared.stopAll()
            await ProcessRegistry.shared.terminateAllAsync()
            sender.reply(toApplicationShouldTerminate: true)
            // Safety watchdog: ensure process terminates if teardown stalls before exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                exit(0)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Fallback synchronous/fire-and-forget cleanup
        Task {
            await ExecutionSupervisor.shared.stopAll()
            await ProcessRegistry.shared.terminateAllAsync()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Private Helpers

    private func snapshotActiveIDs(_ activeIDs: [UUID]) {
        let idStrings = activeIDs.map(\.uuidString)
        UserDefaults.standard.set(idStrings, forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)
    }

    private func snapshotAndTeardown(activeIDs: [UUID]) {
        snapshotActiveIDs(activeIDs)
    }
}
