import SwiftUI
import Testing
@testable import Kuma

// MARK: - KumaShortcutsTests

@Suite("Feature 00 - Category H: Centralized Keyboard Shortcuts Registry")
@MainActor
struct KumaShortcutsTests {

    @Test("TC-H01: Predefined shortcuts have valid titles and display strings")
    func testShortcutCatalogIntegrity() {
        let shortcuts: [KumaShortcut] = [
            KumaShortcuts.settings,
            KumaShortcuts.find,
            KumaShortcuts.newWorkspace,
            KumaShortcuts.help,
            KumaShortcuts.toggleService,
            KumaShortcuts.restartService,
            KumaShortcuts.dismiss
        ]

        for shortcut in shortcuts {
            #expect(!shortcut.title.isEmpty)
            #expect(!shortcut.displayString.isEmpty)
        }
    }

    @Test("TC-H02: Shortcut display strings match expected Apple HIG convention")
    func testShortcutDisplayStrings() {
        #expect(KumaShortcuts.settings.displayString == "⌘,")
        #expect(KumaShortcuts.find.displayString == "⌘F")
        #expect(KumaShortcuts.restartService.displayString == "⌘R")
        #expect(KumaShortcuts.toggleService.displayString == "Space")
        #expect(KumaShortcuts.dismiss.displayString == "Esc")
    }
}
