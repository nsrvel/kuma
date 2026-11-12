import os
import SwiftUI

extension SidebarViewModel {
    public func loadGroups(workspaceID: UUID) async {
        self.currentWorkspaceID = workspaceID
        do {
            self.groups = try await groupRepository.fetchAll(workspaceID: workspaceID)
            rebuildEntries()
            reconcileSelectionForLoadedWorkspace()
        } catch {
            Self.logger.error("Failed to load groups for workspace \(workspaceID): \(error)")
            self.groups = []
            rebuildEntries()
            reconcileSelectionForLoadedWorkspace()
        }
    }

    func reconcileSelectionForLoadedWorkspace() {
        let globalNavIDs: Set<UUID> = [
            .stable("all-services"),
            .stable("starred-services"),
            .stable("settings"),
            .stable("groups"),
        ]

        if let selectedID {
            let selectionIsValid =
                globalNavIDs.contains(selectedID)
                || groups.contains(where: { $0.id == selectedID })
            if !selectionIsValid {
                self.selectedID = .stable("all-services")
            }
        }

        if let editingGroupID,
           !groups.contains(where: { $0.id == editingGroupID }) {
            self.editingGroupID = nil
        }
    }

    public func addGroup(name: String = "New Group", workspaceID: UUID) {
        self.currentWorkspaceID = workspaceID
        let nextSortOrder = (groups.map(\.sortOrder).max() ?? 0) + 1
        let newGroup = ServiceGroup(
            name: name,
            workspaceID: workspaceID,
            sortOrder: nextSortOrder
        )

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            self.groups.append(newGroup)
            self.expandedIDs.insert(.stable("groups"))
            self.editingGroupID = newGroup.id
            self.selectedID = newGroup.id
            self.rebuildEntries()
        }

        Task {
            do {
                try await groupRepository.insert(newGroup)
                NotificationCenter.default.post(name: .kumaGroupsUpdated, object: newGroup.id)
            } catch {
                Self.logger.error("Failed to insert group: \(error)")
            }
        }
    }

    public func renameGroup(id: UUID, newName: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Group" : trimmed

        var updated = groups[index]
        updated.name = finalName
        updated.updatedAt = Date()

        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            self.groups[index] = updated
            self.editingGroupID = nil
            self.rebuildEntries()
        }

        Task {
            do {
                try await groupRepository.update(updated)
                NotificationCenter.default.post(name: .kumaGroupsUpdated, object: id)
            } catch {
                Self.logger.error("Failed to rename group \(id): \(error)")
            }
        }
    }

    public func deleteGroup(id: UUID) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            self.groups.removeAll(where: { $0.id == id })
            if self.selectedID == id {
                self.selectedID = .stable("all-services")
            }
            if self.editingGroupID == id {
                self.editingGroupID = nil
            }
            self.rebuildEntries()
        }

        Task {
            do {
                try await groupRepository.delete(id: id)
                NotificationCenter.default.post(name: .kumaGroupsUpdated, object: id)
            } catch {
                Self.logger.error("Failed to delete group \(id): \(error)")
            }
        }
    }

    public func groupIDForSelectedRow(_ id: UUID?) -> UUID? {
        guard let id else { return nil }
        return groups.first(where: { $0.id == id })?.id
    }
}
