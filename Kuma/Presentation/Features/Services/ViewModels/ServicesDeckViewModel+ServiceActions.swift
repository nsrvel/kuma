import AppKit
import os
import SwiftUI

extension ServicesDeckViewModel {
    public func toggleStarred(id: UUID, workspaceID: UUID) {
        KumaHapticManager.shared.tap()
        if let idx = snapshots.firstIndex(where: { $0.id == id }) {
            snapshots[idx] = snapshots[idx].toggling(starred: !snapshots[idx].isStarred)
        }

        Task {
            do {
                _ = try await serviceRepository.toggleStarred(serviceID: id)
                KumaServiceNotification.postServiceUpdated(serviceID: id, source: KumaServiceNotification.sourceDeck)
            } catch {
                Self.logger.error("Failed to persist toggleStarred for service \(id): \(error.localizedDescription)")
                await refreshSingleServiceSnapshot(id: id)
            }
        }
    }

    public func toggleDisabled(id: UUID, workspaceID: UUID) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        let newDisabled = !snapshots[idx].isDisabled

        let old = snapshots[idx]
        snapshots[idx] = ServiceCardSnapshot(
            id: old.id,
            name: old.name,
            groupIDs: old.groupIDs,
            isDisabled: newDisabled,
            isStarred: old.isStarred,
            subtitle: old.subtitle,
            providerCategory: old.providerCategory,
            portDisplays: old.portDisplays,
            providerOptions: old.providerOptions,
            createdAt: old.createdAt,
            searchKey: old.searchKey
        )

        if newDisabled {
            stateStore?.setExecutionState(.idle, for: id)
        }

        Task {
            do {
                if var svc = try await serviceRepository.fetchService(id: id) {
                    svc.isDisabled = newDisabled
                    svc.updatedAt = Date()
                    try await serviceRepository.updateService(svc)
                    KumaServiceNotification.postServiceUpdated(serviceID: id, source: KumaServiceNotification.sourceDeck)
                }
            } catch {
                Self.logger.error("Failed to toggle disabled for service \(id): \(error)")
                await refreshSingleServiceSnapshot(id: id)
            }
        }
    }

    public func switchProvider(serviceID: UUID, providerID: UUID, workspaceID: UUID) {
        let isCurrentlyRunning = isOperational(serviceID)

        Task {
            do {
                if isCurrentlyRunning {
                    stateStore?.setExecutionState(.stopping, for: serviceID)
                    await ServiceStopSupport.stopOffMainActor(serviceID: serviceID, stateStore: stateStore)
                }

                if var svc = try await serviceRepository.fetchService(id: serviceID) {
                    svc.activeProviderID = providerID
                    svc.updatedAt = Date()
                    try await serviceRepository.updateService(svc)
                    await refreshSingleServiceSnapshot(id: serviceID)
                    KumaServiceNotification.postServiceUpdated(serviceID: serviceID, source: KumaServiceNotification.sourceDeck)

                    if isCurrentlyRunning {
                        stateStore?.setExecutionState(.starting, for: serviceID)
                        try await ServiceExecutionEngine.shared.start(serviceID: serviceID)
                        await ServiceExecutionStateSync.applyAfterSuccessfulStart(
                            serviceID: serviceID,
                            stateStore: stateStore
                        )
                    }
                }
            } catch {
                Self.logger.error("Failed to switch provider for service \(serviceID): \(error)")
                stateStore?.setExecutionState(.crashed(exitCode: 1), for: serviceID)
                await refreshSingleServiceSnapshot(id: serviceID)
            }
        }
    }

    public func toggleGroup(serviceID: UUID, groupID: UUID, workspaceID: UUID) {
        guard let idx = snapshots.firstIndex(where: { $0.id == serviceID }) else { return }

        let old = snapshots[idx]
        var updatedGroupIDs = old.groupIDs
        if updatedGroupIDs.contains(groupID) {
            updatedGroupIDs.remove(groupID)
        } else {
            updatedGroupIDs.insert(groupID)
        }

        snapshots[idx] = ServiceCardSnapshot(
            id: old.id,
            name: old.name,
            groupIDs: updatedGroupIDs,
            isDisabled: old.isDisabled,
            isStarred: old.isStarred,
            subtitle: old.subtitle,
            providerCategory: old.providerCategory,
            portDisplays: old.portDisplays,
            providerOptions: old.providerOptions,
            createdAt: old.createdAt,
            searchKey: old.searchKey
        )

        if filterGroupID != nil {
            recomputeFilteredSnapshots()
        }

        Task {
            do {
                _ = try await serviceRepository.toggleGroupMembership(serviceID: serviceID, groupID: groupID)
                await refreshSingleServiceSnapshot(id: serviceID)
                KumaServiceNotification.postServiceUpdated(serviceID: serviceID, source: KumaServiceNotification.sourceDeck)
            } catch {
                Self.logger.error("Failed to toggle group membership for service \(serviceID): \(error)")
                await refreshSingleServiceSnapshot(id: serviceID)
            }
        }
    }

    public func duplicateService(id: UUID, workspaceID: UUID) {
        guard let original = snapshots.first(where: { $0.id == id }) else { return }

        let newServiceID = UUID()
        let copyName = "\(original.name) (Copy)"
        let optimisticSnapshot = ServiceCardSnapshot(
            id: newServiceID,
            name: copyName,
            groupIDs: original.groupIDs,
            isDisabled: original.isDisabled,
            isStarred: original.isStarred,
            subtitle: original.subtitle,
            providerCategory: original.providerCategory,
            portDisplays: original.portDisplays,
            providerOptions: original.providerOptions,
            createdAt: Date(),
            searchKey: Self.duplicateSearchKey(from: original.searchKey, originalName: original.name, copyName: copyName)
        )

        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            snapshots.append(optimisticSnapshot)
            recomputeFilteredSnapshots()
        }

        Task {
            do {
                _ = try await serviceRepository.duplicateService(sourceID: id, newID: newServiceID)
                await refreshSingleServiceSnapshot(id: newServiceID)
                recomputeFilteredSnapshots()
                NotificationCenter.default.post(name: .kumaServiceCreated, object: newServiceID)
            } catch {
                Self.logger.error("Failed to duplicate service \(id): \(error)")
                snapshots.removeAll(where: { $0.id == newServiceID })
                recomputeFilteredSnapshots()
                await refreshSingleServiceSnapshot(id: id)
            }
        }
    }

    public func copyConfig(id: UUID) {
        Task { @MainActor in
            do {
                let dataPort = DataPortRepository()
                let jsonString = try await dataPort.exportSingleServiceJSON(serviceID: id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(jsonString, forType: .string)
                NSSound(named: "Purr")?.play()
            } catch {
                Self.logger.error("Failed to copy config for service \(id): \(error)")
            }
        }
    }

    public func promptDeleteService(id: UUID) {
        if let snapshot = snapshots.first(where: { $0.id == id }) {
            self.servicePendingDeletion = snapshot
        }
    }

    public func confirmDeletePendingService(workspaceID: UUID) {
        guard let pending = servicePendingDeletion else { return }
        let id = pending.id
        self.servicePendingDeletion = nil
        deleteService(id: id, workspaceID: workspaceID)
    }

    public func deleteService(id: UUID, workspaceID: UUID) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            snapshots.removeAll(where: { $0.id == id })
            stateStore?.removeService(id)
            if selectedServiceID == id {
                selectedServiceID = nil
                isInspectorPresented = false
            }
        }

        Task {
            do {
                try await serviceRepository.deleteService(id: id)
                NotificationCenter.default.post(name: .kumaServiceDeleted, object: id)
            } catch {
                Self.logger.error("Failed to delete service \(id): \(error)")
                await refreshSingleServiceSnapshot(id: id)
                recomputeFilteredSnapshots()
            }
        }
    }

    public func selectService(_ id: UUID?) {
        self.selectedServiceID = id
        self.isInspectorPresented = (id != nil)
    }
}
