import os
import SwiftUI

extension SidebarViewModel {
    public func moveGroups(fromOffsets source: IndexSet, toOffset destination: Int) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            self.groups.move(fromOffsets: source, toOffset: destination)
            for (index, _) in self.groups.enumerated() {
                self.groups[index].sortOrder = index
                self.groups[index].updatedAt = Date()
            }
            self.rebuildEntries()
        }

        let orders = self.groups.enumerated().map { (index, group) in
            (id: group.id, sortOrder: index)
        }
        Task {
            do {
                try await groupRepository.updateSortOrders(orders)
                NotificationCenter.default.post(name: .kumaGroupsUpdated, object: nil)
            } catch {
                Self.logger.error("Failed to persist group reorder: \(error)")
            }
        }
    }

    public func moveGroupUp(id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }), index > 0 else { return }
        moveGroups(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
    }

    public func moveGroupDown(id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }), index < groups.count - 1 else { return }
        moveGroups(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
    }

    public func canMoveGroupUp(id: UUID) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        return index > 0
    }

    public func canMoveGroupDown(id: UUID) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        return index < groups.count - 1
    }

    public func reorderGroup(draggedID: UUID, targetID: UUID) {
        guard draggedID != targetID,
              let fromIndex = groups.firstIndex(where: { $0.id == draggedID }),
              let toIndex = groups.firstIndex(where: { $0.id == targetID }) else { return }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        moveGroups(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
    }
}
