import SwiftUI

public struct KumaCommands: Commands {
    let coordinator: AppCoordinator
    let workspaceStore: WorkspaceStore

    public init(coordinator: AppCoordinator, workspaceStore: WorkspaceStore) {
        self.coordinator = coordinator
        self.workspaceStore = workspaceStore
    }

    public var body: some Commands {
        // 0. App Settings Menu & Shortcut (⌘,)
        CommandGroup(replacing: .appSettings) {
            Button(KumaShortcuts.settings.title) {
                NotificationCenter.default.post(name: .kumaOpenSettings, object: nil)
            }
            .keyboardShortcut(KumaShortcuts.settings.key, modifiers: KumaShortcuts.settings.modifiers)
        }

        // 0.1 Standard Edit / Find Menu & Shortcut (⌘F)
        CommandGroup(after: .textEditing) {
            Button(KumaShortcuts.find.title) {
                NotificationCenter.default.post(name: .kumaFocusSearch, object: nil)
            }
            .keyboardShortcut(KumaShortcuts.find.key, modifiers: KumaShortcuts.find.modifiers)
        }


        // 1. Workspaces Menu & Global Keyboard Shortcuts (⌘1, ⌘2, ⌘3...)
        CommandMenu("Workspaces") {
            ForEach(Array(workspaceStore.workspaces.enumerated()), id: \.element.id) { index, ws in
                if index < 9 {
                    Button(ws.name) {
                        workspaceStore.selectWorkspace(ws)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                } else {
                    Button(ws.name) {
                        workspaceStore.selectWorkspace(ws)
                    }
                }
            }

            Divider()

            Button("New Workspace…") {
                workspaceStore.showCreateSheet = true
            }
            .keyboardShortcut(KumaShortcuts.newWorkspace.key, modifiers: KumaShortcuts.newWorkspace.modifiers)
        }

        // 2. Help Menu — re-show the onboarding guide
        CommandGroup(replacing: .help) {
            Button(KumaShortcuts.help.title) {
                coordinator.resetToOnboarding()
                NotificationCenter.default.post(name: .kumaOpenOnboarding, object: nil)
            }
            .keyboardShortcut(KumaShortcuts.help.key, modifiers: KumaShortcuts.help.modifiers)
        }
    }
}
