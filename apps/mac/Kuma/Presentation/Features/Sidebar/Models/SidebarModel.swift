import SwiftUI

// MARK: - SidebarIcon

public enum SidebarIcon: Hashable, Sendable {
    case system(String)
    case asset(String)
}

// MARK: - SidebarAction

public struct SidebarAction: Identifiable, Sendable {
    public let id: UUID
    public let icon: String        // SF Symbol name
    public let tooltip: String
    public let handler: @MainActor @Sendable () -> Void

    public init(id: UUID = UUID(), icon: String, tooltip: String, handler: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.icon = icon
        self.tooltip = tooltip
        self.handler = handler
    }
}

extension SidebarAction: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: SidebarAction, rhs: SidebarAction) -> Bool { lhs.id == rhs.id }
}

// MARK: - SidebarNode

public struct SidebarNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var icon: SidebarIcon
    public var children: [SidebarEntry]?
    public var actions: [SidebarAction]
    public var isSpecialHeader: Bool
    public var isExpandedByDefault: Bool
    public var isGroupRow: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        icon: SidebarIcon,
        children: [SidebarEntry]? = nil,
        actions: [SidebarAction] = [],
        isSpecialHeader: Bool = false,
        isExpandedByDefault: Bool = true,
        isGroupRow: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.children = children
        self.actions = actions
        self.isSpecialHeader = isSpecialHeader
        self.isExpandedByDefault = isExpandedByDefault
        self.isGroupRow = isGroupRow
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(icon)
        hasher.combine(isSpecialHeader)
        hasher.combine(isExpandedByDefault)
        hasher.combine(isGroupRow)
    }

    public static func == (lhs: SidebarNode, rhs: SidebarNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.icon == rhs.icon &&
        lhs.isSpecialHeader == rhs.isSpecialHeader &&
        lhs.isExpandedByDefault == rhs.isExpandedByDefault &&
        lhs.isGroupRow == rhs.isGroupRow &&
        lhs.children == rhs.children
    }
}

// MARK: - SidebarEntry

public enum SidebarEntry: Identifiable, Hashable, Sendable {
    case item(SidebarNode)
    case divider(id: UUID = UUID())

    public var id: UUID {
        switch self {
        case .item(let node):
            return node.id
        case .divider(let id):
            return id
        }
    }
}
