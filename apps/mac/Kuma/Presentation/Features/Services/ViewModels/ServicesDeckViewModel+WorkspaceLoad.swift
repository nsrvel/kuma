import Foundation
import os

extension ServicesDeckViewModel {
    public func loadWorkspace(workspaceID: UUID) {
        loadTask?.cancel()
        loadTask = Task {
            await loadWorkspaceAsync(workspaceID: workspaceID)
        }
    }

    public func refreshGroups(workspaceID: UUID) async {
        do {
            groups = try await groupRepository.fetchAll(workspaceID: workspaceID)
        } catch {
            Self.logger.error("Failed to refresh groups for workspace \(workspaceID): \(error.localizedDescription)")
        }
    }

    public func loadWorkspaceAsync(workspaceID: UUID) async {
        do {
            async let loadedItems = serviceRepository.fetchDeckItems(forWorkspace: workspaceID)
            async let loadedGroups = groupRepository.fetchAll(workspaceID: workspaceID)

            let (deckItems, groups) = try await (loadedItems, loadedGroups)
            let loaded = deckItems.asCardSnapshots
            guard !Task.isCancelled else { return }

            let serviceIDs = loaded.map(\.id)
            if let store = self.stateStore {
                await store.refreshProcessStates(for: serviceIDs)
            }

            let isFirstLoad = !self.hasInitialLoaded
            self.groups = groups
            self.snapshots = loaded
            self.hasInitialLoaded = true

            if isFirstLoad && KumaSettingsKey.bool(forKey: KumaSettingsKey.autoResumeServices, defaultValue: false, defaults: self.userDefaults) {
                resumeServicesIfNeeded(loadedSnapshots: loaded)
            }
        } catch {
            guard !Task.isCancelled else { return }
            Self.logger.error("Failed to load workspace \(workspaceID): \(error.localizedDescription)")
            self.snapshots = []
            self.hasInitialLoaded = true
        }
    }

    func resumeServicesIfNeeded(loadedSnapshots: [ServiceCardSnapshot]) {
        guard let savedStrings = userDefaults.stringArray(forKey: KumaSettingsKey.activeServiceIDsBeforeQuit),
              !savedStrings.isEmpty else { return }

        let savedUUIDs = Set(savedStrings.compactMap(UUID.init))
        let candidates = loadedSnapshots.filter { !($0.isDisabled) && savedUUIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }

        let remaining = savedUUIDs.subtracting(candidates.map(\.id))
        userDefaults.set(remaining.map(\.uuidString), forKey: KumaSettingsKey.activeServiceIDsBeforeQuit)

        Task {
            for snapshot in candidates {
                guard !isOperational(snapshot.id) else { continue }
                stateStore?.setExecutionState(.starting, for: snapshot.id)
                do {
                    try await ServiceExecutionEngine.shared.start(serviceID: snapshot.id)
                    await ServiceExecutionStateSync.applyAfterSuccessfulStart(
                        serviceID: snapshot.id,
                        stateStore: stateStore
                    )
                } catch {
                    Self.logger.error("Auto-start failed for '\(snapshot.name)': \(error.localizedDescription)")
                    stateStore?.setExecutionState(.crashed(exitCode: 1), for: snapshot.id)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    public func refreshSingleServiceSnapshot(id: UUID) async {
        do {
            if let updated = try await serviceRepository.fetchDeckItem(serviceID: id) {
                let snapshot = ServiceCardSnapshot(deckItem: updated)
                if let idx = snapshots.firstIndex(where: { $0.id == id }) {
                    snapshots[idx] = snapshot
                } else {
                    snapshots.append(snapshot)
                }
            } else {
                snapshots.removeAll(where: { $0.id == id })
            }
            if let store = stateStore {
                await store.refreshProcessStates(for: [id])
            }
        } catch {
            Self.logger.error("Failed to reload single service snapshot \(id): \(error.localizedDescription)")
        }
    }
}
