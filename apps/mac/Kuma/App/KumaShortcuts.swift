import SwiftUI

// MARK: - KumaShortcut

/// Strongly typed keyboard shortcut descriptor providing both SwiftUI event bindings
/// and user-facing display strings for tooltips, menus, and search bar badges.
public struct KumaShortcut: Sendable, Equatable {
    public let title: String
    public let key: KeyEquivalent
    public let modifiers: EventModifiers
    public let displayString: String

    public init(
        title: String,
        key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        displayString: String
    ) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.displayString = displayString
    }
}

// MARK: - KumaShortcuts Catalog

/// Centralized catalog of all global and contextual keyboard shortcuts in Kuma.
public enum KumaShortcuts {
    // MARK: - Global App & Navigation
    public static let settings = KumaShortcut(
        title: "Settings…",
        key: ",",
        modifiers: .command,
        displayString: "⌘,"
    )

    public static let find = KumaShortcut(
        title: "Find Services…",
        key: "f",
        modifiers: .command,
        displayString: "⌘F"
    )

    public static let newWorkspace = KumaShortcut(
        title: "New Workspace",
        key: "n",
        modifiers: [.command, .shift],
        displayString: "⇧⌘N"
    )

    public static let help = KumaShortcut(
        title: "Kuma Onboarding Guide",
        key: "?",
        modifiers: .command,
        displayString: "⌘?"
    )

    // MARK: - Service Lifecycle & Deck
    public static let toggleService = KumaShortcut(
        title: "Toggle Service",
        key: .space,
        modifiers: [],
        displayString: "Space"
    )

    public static let restartService = KumaShortcut(
        title: "Restart Service",
        key: "r",
        modifiers: .command,
        displayString: "⌘R"
    )

    public static let dismiss = KumaShortcut(
        title: "Deselect / Dismiss",
        key: .escape,
        modifiers: [],
        displayString: "Esc"
    )
}
