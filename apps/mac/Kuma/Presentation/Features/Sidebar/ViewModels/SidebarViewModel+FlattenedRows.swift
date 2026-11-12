import SwiftUI

extension SidebarViewModel {
    public struct FlattenedRow: Identifiable, Equatable {
        public let id: UUID
        public let entry: SidebarEntry
        public let indentLevel: Int
        public let isPlaceholder: Bool
        public let hasDividerAfter: Bool

        public var isNavigable: Bool {
            switch entry {
            case .item: return !isPlaceholder
            case .divider: return false
            }
        }
    }

    func rebuildEntries() {
        let groupChildren: [SidebarEntry] = groups.map { group in
            .item(SidebarNode(
                id: group.id,
                title: group.name,
                icon: .system("folder"),
                children: nil,
                isGroupRow: true
            ))
        }

        let groupsHeader = SidebarNode(
            id: .stable("groups"),
            title: "Groups",
            icon: .system("folder"),
            children: groupChildren,
            actions: [
                SidebarAction(icon: "plus", tooltip: "New Group") { [weak self] in
                    guard let self, let wsID = self.currentWorkspaceID else { return }
                    self.addGroup(workspaceID: wsID)
                }
            ],
            isSpecialHeader: true,
            isExpandedByDefault: true
        )

        self.entries = [
            .item(SidebarNode(
                id: .stable("all-services"),
                title: "All Services",
                icon: .system("square.grid.2x2.fill"),
                children: nil
            )),
            .item(SidebarNode(
                id: .stable("starred-services"),
                title: "Starred",
                icon: .system("star"),
                children: nil
            )),
            .item(groupsHeader)
        ]
    }

    func rebuildFlattenedRows() {
        var result: [FlattenedRow] = []

        func appendEntry(_ entry: SidebarEntry, indentLevel: Int) {
            if case .divider = entry {
                result.append(
                    FlattenedRow(
                        id: entry.id,
                        entry: entry,
                        indentLevel: indentLevel,
                        isPlaceholder: false,
                        hasDividerAfter: false
                    )
                )
                return
            }

            result.append(
                FlattenedRow(
                    id: entry.id,
                    entry: entry,
                    indentLevel: indentLevel,
                    isPlaceholder: false,
                    hasDividerAfter: false
                )
            )

            if case .item(let node) = entry, let children = node.children, isExpanded(node.id) {
                if children.isEmpty {
                    let placeholderId = UUID.stable(node.id.uuidString + ".empty-placeholder")
                    let placeholderNode = SidebarNode(
                        id: placeholderId,
                        title: emptyPlaceholderText(for: node),
                        icon: .system("")
                    )
                    result.append(
                        FlattenedRow(
                            id: placeholderId,
                            entry: .item(placeholderNode),
                            indentLevel: indentLevel + 1,
                            isPlaceholder: true,
                            hasDividerAfter: false
                        )
                    )
                } else {
                    for child in children {
                        appendEntry(child, indentLevel: indentLevel + 1)
                    }
                }
            }
        }

        for (index, entry) in entries.enumerated() {
            if case .divider = entry {
                continue
            }

            let startCount = result.count
            appendEntry(entry, indentLevel: 0)

            let nextIndex = index + 1
            if nextIndex < entries.count, case .divider = entries[nextIndex] {
                if result.count > startCount, let lastIndex = result.indices.last {
                    result[lastIndex] = FlattenedRow(
                        id: result[lastIndex].id,
                        entry: result[lastIndex].entry,
                        indentLevel: result[lastIndex].indentLevel,
                        isPlaceholder: result[lastIndex].isPlaceholder,
                        hasDividerAfter: true
                    )
                }
            }
        }

        self.flattenedRows = result
    }

    func emptyPlaceholderText(for node: SidebarNode) -> String {
        if node.title == "Starred" {
            return "No starred items"
        } else if node.title == "All Services" {
            return "No services"
        } else {
            return "No \(node.title.lowercased()) services"
        }
    }

    public func handleMove(_ direction: MoveCommandDirection) {
        let navigableRows = flattenedRows.filter { $0.isNavigable }
        guard !navigableRows.isEmpty else { return }

        let currentIndex = navigableRows.firstIndex(where: { $0.id == selectedID })

        switch direction {
        case .down:
            if let index = currentIndex {
                let nextIndex = index + 1
                if nextIndex < navigableRows.count {
                    selectedID = navigableRows[nextIndex].id
                }
            } else {
                selectedID = navigableRows.first?.id
            }
        case .up:
            if let index = currentIndex {
                let prevIndex = index - 1
                if prevIndex >= 0 {
                    selectedID = navigableRows[prevIndex].id
                }
            } else {
                selectedID = navigableRows.last?.id
            }
        case .left:
            if let selectedID,
               let row = navigableRows.first(where: { $0.id == selectedID }),
               case .item(let node) = row.entry,
               node.children != nil,
               isExpanded(selectedID) {
                _ = expandedIDs.remove(selectedID)
            }
        case .right:
            if let selectedID,
               let row = navigableRows.first(where: { $0.id == selectedID }),
               case .item(let node) = row.entry,
               node.children != nil,
               !isExpanded(selectedID) {
                _ = expandedIDs.insert(selectedID)
            }
        default:
            break
        }
    }

    public static func makeDefault() -> SidebarViewModel {
        SidebarViewModel(
            selectedID: .stable("all-services"),
            expandedIDs: []
        )
    }
}
