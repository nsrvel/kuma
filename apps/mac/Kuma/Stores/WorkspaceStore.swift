import Foundation
import Observation
import os

@MainActor
@Observable
public final class WorkspaceStore {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "WorkspaceStore")
    public static let selectedWorkspaceKey = "kuma.selectedWorkspaceId.storage"

    private let userDefaults: UserDefaults
    private let repository: any WorkspaceRepositoryProtocol

    public private(set) var workspaces: [Workspace] = []
    public var selectedWorkspaceId: UUID? {
        didSet {
            if let selectedWorkspaceId {
                userDefaults.set(selectedWorkspaceId.uuidString, forKey: Self.selectedWorkspaceKey)
            }
        }
    }
    public var showCreateSheet: Bool = false
    public var workspaceToEdit: Workspace? = nil

    public var activeWorkspace: Workspace? {
        workspaces.first(where: { $0.id == selectedWorkspaceId }) ?? workspaces.first
    }

    private var mutationTask: Task<Void, Never>? = nil

    public init(
        initialWorkspaces: [Workspace]? = nil,
        repository: any WorkspaceRepositoryProtocol = WorkspaceRepository(),
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.userDefaults = userDefaults

        if let initial = initialWorkspaces {
            self.workspaces = initial
            self.selectedWorkspaceId = initial.first?.id
        } else {
            loadFromDatabase()
        }
    }

    public func loadFromDatabase() {
        mutationTask?.cancel()
        mutationTask = Task {
            do {
                let fetched = try await repository.fetchAll()
                guard !Task.isCancelled else { return }
                if !fetched.isEmpty {
                    self.workspaces = fetched
                    let savedSelectedStr = userDefaults.string(forKey: Self.selectedWorkspaceKey)
                    if let savedUUID = savedSelectedStr.flatMap(UUID.init), fetched.contains(where: { $0.id == savedUUID }) {
                        self.selectedWorkspaceId = savedUUID
                    } else {
                        self.selectedWorkspaceId = fetched.first?.id
                    }
                } else {
                    let defaultWS = Workspace.defaultWorkspace
                    do {
                        try await repository.insert(defaultWS)
                        guard !Task.isCancelled else { return }
                        self.workspaces = [defaultWS]
                        self.selectedWorkspaceId = defaultWS.id
                    } catch {
                        Self.logger.error("Failed to insert default workspace: \(error.localizedDescription)")
                        AlertService.shared.showError(title: "Database Error", message: "Failed to create default workspace: \(error.localizedDescription)")
                    }
                }
            } catch {
                Self.logger.error("Failed to load workspaces from DB: \(error.localizedDescription)")
                AlertService.shared.showError(title: "Database Error", message: "Failed to load workspaces: \(error.localizedDescription)")
            }
        }
    }

    public func selectWorkspace(_ workspace: Workspace) {
        Self.logger.info("Selected workspace: \(workspace.name)")
        self.selectedWorkspaceId = workspace.id
    }

    public func addWorkspace(name: String, imagePath: String? = nil) -> Workspace {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Workspace" : trimmed
        let newWorkspaceID = UUID()

        // If a file URL was provided, save a managed copy into internal storage
        var finalImageFileName: String? = nil
        if let imagePath, let url = URL(string: imagePath), url.isFileURL {
            finalImageFileName = WorkspaceImageStore.shared.saveWorkspaceImage(from: url, workspaceID: newWorkspaceID)
        } else {
            finalImageFileName = imagePath
        }

        let newWorkspace = Workspace(id: newWorkspaceID, name: finalName, imagePath: finalImageFileName, sortOrder: workspaces.count)
        self.workspaces.append(newWorkspace)
        self.selectedWorkspaceId = newWorkspace.id

        Task {
            do {
                try await repository.insert(newWorkspace)
            } catch {
                Self.logger.error("Failed to insert workspace \(newWorkspace.id): \(error.localizedDescription)")
                AlertService.shared.showError(title: "Save Failed", message: "Could not save workspace: \(error.localizedDescription)")
            }
        }
        Self.logger.info("Added new workspace: \(finalName)")
        return newWorkspace
    }

    public func renameWorkspace(_ workspace: Workspace, newName: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index].name = newName
        workspaces[index].updatedAt = Date()
        let updated = workspaces[index]

        Task {
            do {
                try await repository.update(updated)
            } catch {
                Self.logger.error("Failed to rename workspace \(workspace.id): \(error.localizedDescription)")
                AlertService.shared.showError(title: "Update Failed", message: "Could not rename workspace: \(error.localizedDescription)")
            }
        }
        Self.logger.info("Renamed workspace \(workspace.id) to \(newName)")
    }

    public func updateWorkspace(_ workspace: Workspace, newExternalImageURL: URL? = nil) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        var updated = workspace

        if let newExternalImageURL {
            // Delete previous image file if it exists to avoid leaking storage
            if let oldImagePath = updated.imagePath {
                WorkspaceImageStore.shared.deleteImage(for: oldImagePath)
            }
            let managedFileName = WorkspaceImageStore.shared.saveWorkspaceImage(from: newExternalImageURL, workspaceID: workspace.id)
            updated.imagePath = managedFileName
        }

        updated.updatedAt = Date()
        workspaces[index] = updated

        Task {
            do {
                try await repository.update(updated)
            } catch {
                Self.logger.error("Failed to update workspace \(workspace.id): \(error.localizedDescription)")
                AlertService.shared.showError(title: "Update Failed", message: "Could not update workspace: \(error.localizedDescription)")
            }
        }
        Self.logger.info("Updated workspace: \(updated.name)")
    }

    public func deleteWorkspace(_ workspace: Workspace) {
        // Invariant Rule: App must never have 0 workspaces
        guard workspaces.count > 1 else {
            Self.logger.warning("Attempted to delete the sole remaining workspace \(workspace.id). Operation blocked.")
            return
        }

        if let imagePath = workspace.imagePath {
            WorkspaceImageStore.shared.deleteImage(for: imagePath)
        }

        workspaces.removeAll { $0.id == workspace.id }

        if selectedWorkspaceId == workspace.id {
            selectedWorkspaceId = workspaces.first?.id
        }

        Task {
            do {
                try await repository.delete(id: workspace.id)
            } catch {
                Self.logger.error("Failed to delete workspace \(workspace.id): \(error.localizedDescription)")
                AlertService.shared.showError(title: "Delete Failed", message: "Could not delete workspace: \(error.localizedDescription)")
            }
        }
        Self.logger.info("Deleted workspace: \(workspace.name)")
    }

    public func moveWorkspace(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < workspaces.count,
              destinationIndex >= 0, destinationIndex < workspaces.count,
              sourceIndex != destinationIndex else { return }

        workspaces.swapAt(sourceIndex, destinationIndex)

        var ordersToUpdate: [(id: UUID, sortOrder: Int)] = []
        ordersToUpdate.reserveCapacity(workspaces.count)

        for (index, _) in workspaces.enumerated() {
            workspaces[index].sortOrder = index
            workspaces[index].updatedAt = Date()
            ordersToUpdate.append((id: workspaces[index].id, sortOrder: index))
        }

        Task {
            do {
                try await repository.updateSortOrders(ordersToUpdate)
            } catch {
                Self.logger.error("Failed to update sort orders: \(error.localizedDescription)")
                AlertService.shared.showError(title: "Reorder Failed", message: "Could not save workspace order: \(error.localizedDescription)")
            }
        }
    }
}
