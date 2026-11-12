import SwiftUI
import Observation
import os

@MainActor
@Observable
public final class SidebarViewModel {
    static let logger = Logger(subsystem: "lokastudio.kuma", category: "SidebarViewModel")

    public var entries: [SidebarEntry] = [] {
        didSet { rebuildFlattenedRows() }
    }
    public var selectedID: UUID?
    public var expandedIDs: Set<UUID> = [] {
        didSet { rebuildFlattenedRows() }
    }
    public var flattenedRows: [FlattenedRow] = []
    public var groups: [ServiceGroup] = []
    public var editingGroupID: UUID? = nil

    let groupRepository: any ServiceGroupRepositoryProtocol
    var currentWorkspaceID: UUID? = nil

    public init(
        entries: [SidebarEntry] = [],
        selectedID: UUID? = nil,
        expandedIDs: Set<UUID> = [],
        groupRepository: any ServiceGroupRepositoryProtocol = ServiceGroupRepository()
    ) {
        self.groupRepository = groupRepository
        self.selectedID = selectedID ?? .stable("all-services")

        if entries.isEmpty {
            self.entries = []
            self.rebuildEntries()
        } else {
            self.entries = entries
        }

        var initialExpanded = expandedIDs
        if expandedIDs.isEmpty {
            for entry in self.entries {
                if case .item(let node) = entry, node.isExpandedByDefault {
                    initialExpanded.insert(node.id)
                }
            }
        }
        self.expandedIDs = initialExpanded
        self.rebuildFlattenedRows()
    }

    public func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    public func isExpanded(_ id: UUID) -> Bool {
        expandedIDs.contains(id)
    }
}
