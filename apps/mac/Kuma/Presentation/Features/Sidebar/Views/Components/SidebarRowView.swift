import SwiftUI

public struct SidebarRowView: View {
    public let node: SidebarNode
    public let isSelected: Bool
    public let isExpanded: Bool
    public let isEditing: Bool
    public let indentLevel: Int
    public let onSelect: () -> Void
    public let onToggleExpand: () -> Void
    public let onAddAction: (() -> Void)?
    public let onCommitRename: (String) -> Void
    public let onStartRename: () -> Void
    public let onDelete: () -> Void
    public let onMoveUp: (() -> Void)?
    public let onMoveDown: (() -> Void)?
    public let onReorderGroup: ((UUID, UUID) -> Void)?

    @State private var isHovering = false
    @State private var isDropTargeted = false

    public init(
        node: SidebarNode,
        isSelected: Bool,
        isExpanded: Bool,
        isEditing: Bool = false,
        indentLevel: Int,
        onSelect: @escaping () -> Void,
        onToggleExpand: @escaping () -> Void,
        onAddAction: (() -> Void)? = nil,
        onCommitRename: @escaping (String) -> Void = { _ in },
        onStartRename: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onReorderGroup: ((UUID, UUID) -> Void)? = nil
    ) {
        self.node = node
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.isEditing = isEditing
        self.indentLevel = indentLevel
        self.onSelect = onSelect
        self.onToggleExpand = onToggleExpand
        self.onAddAction = onAddAction
        self.onCommitRename = onCommitRename
        self.onStartRename = onStartRename
        self.onDelete = onDelete
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onReorderGroup = onReorderGroup
    }

    private var hasChildren: Bool { node.children != nil }
    private var showActions: Bool { hasChildren ? (isHovering || isSelected) : isHovering }
    private var showChevronActive: Bool { isHovering || isSelected }

    public var body: some View {
        ZStack(alignment: .leading) {
            if isEditing {
                SidebarRowInlineEditor(node: node, indentLevel: indentLevel, onCommitRename: onCommitRename)
            } else {
                contentRow
            }

            SidebarRowActionButtons(
                node: node,
                showActions: showActions,
                hasChildren: hasChildren,
                isExpanded: isExpanded,
                showChevronActive: showChevronActive,
                onAddAction: onAddAction,
                onToggleExpand: onToggleExpand
            )
        }
        .frame(minHeight: KumaTheme.Sidebar.rowMinHeight)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: KumaTheme.Sidebar.rowCornerRadius, style: .continuous))
        .overlay {
            if isDropTargeted {
                SidebarDropIndicator()
            }
        }
        .scaleEffect(isDropTargeted ? 1.02 : 1.0)
        .foregroundStyle(rowForeground)
        .onHover { isHovering = $0 }
        .contextMenu {
            if node.isGroupRow {
                Button("Rename") { onStartRename() }
                if let onMoveUp { Button("Move Up") { onMoveUp() } }
                if let onMoveDown { Button("Move Down") { onMoveDown() } }
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isDropTargeted)
        .animation(.easeInOut(duration: 0.14), value: isSelected)
        .accessibilityLabel(node.title)
        .accessibilityAddTraits(node.isSpecialHeader ? .isHeader : .isButton)
        .modifier(GroupDragDropModifier(isGroupRow: node.isGroupRow, nodeID: node.id, onReorder: onReorderGroup, isTargeted: $isDropTargeted))
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted {
                KumaHapticManager.shared.alignment()
            }
        }
    }

    private var contentRow: some View {
        HStack(spacing: 0) {
            if indentLevel > 0 {
                Spacer().frame(width: CGFloat(indentLevel) * KumaTheme.Sidebar.indentWidth)
            }

            if !node.isSpecialHeader {
                SidebarRowIcon(icon: node.icon)
                    .frame(width: 18, height: 18)
                    .padding(.trailing, 8)
            }

            Text(node.title)
                .font(node.isSpecialHeader ? .system(size: 12, weight: .medium) : .system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.vertical, node.isSpecialHeader ? 6 : KumaTheme.Sidebar.rowVerticalPadding)
        .padding(.leading, KumaTheme.Sidebar.rowHorizontalPadding)
        .padding(.trailing, hasChildren ? 48 : (node.isSpecialHeader ? 44 : KumaTheme.Sidebar.rowHorizontalPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isSpecialHeader { onToggleExpand() } else { onSelect() }
        }
    }

    private var rowBackground: some ShapeStyle {
        if node.isSpecialHeader { return AnyShapeStyle(Color.clear) }
        if isSelected { return AnyShapeStyle(Color.secondary.opacity(KumaTheme.Sidebar.selectedBgOpacity)) }
        return isHovering ? AnyShapeStyle(Color.secondary.opacity(KumaTheme.Sidebar.hoverBgOpacity)) : AnyShapeStyle(Color.clear)
    }

    private var rowForeground: some ShapeStyle {
        if node.isSpecialHeader { return AnyShapeStyle(Color.primary.opacity(0.88)) }
        return (isSelected || isHovering) ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary)
    }
}
