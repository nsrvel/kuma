import SwiftUI

public struct SidebarRowActionButtons: View {
    public let node: SidebarNode
    public let showActions: Bool
    public let hasChildren: Bool
    public let isExpanded: Bool
    public let showChevronActive: Bool
    public let onAddAction: (() -> Void)?
    public let onToggleExpand: () -> Void

    public init(
        node: SidebarNode,
        showActions: Bool,
        hasChildren: Bool,
        isExpanded: Bool,
        showChevronActive: Bool,
        onAddAction: (() -> Void)?,
        onToggleExpand: @escaping () -> Void
    ) {
        self.node = node
        self.showActions = showActions
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
        self.showChevronActive = showChevronActive
        self.onAddAction = onAddAction
        self.onToggleExpand = onToggleExpand
    }

    public var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)

            if showActions && !node.actions.isEmpty {
                ForEach(node.actions) { action in
                    SidebarActionButton(
                        icon: action.icon,
                        tooltip: action.tooltip
                    ) {
                        if let onAddAction {
                            onAddAction()
                        } else {
                            action.handler()
                        }
                    }
                }
            }
            if hasChildren {
                SidebarChevron(isExpanded: isExpanded, onToggle: onToggleExpand)
                    .opacity(showChevronActive ? 1.0 : 0.0)
            }
        }
        .padding(.trailing, KumaTheme.Sidebar.rowHorizontalPadding)
    }
}
