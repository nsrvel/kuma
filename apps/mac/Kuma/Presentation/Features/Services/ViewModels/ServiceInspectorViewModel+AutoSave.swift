import Foundation
import os

extension ServiceInspectorViewModel {
    public func cancelAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    public func flushPendingAutoSave() async {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        if pendingSaveRevision != lastCommittedRevision {
            await commitChanges()
        }
    }

    public func scheduleAutoSave(portsTouched: Bool = false) {
        if portsTouched {
            portsDraftDirty = true
        }
        if !configurationIssues.isEmpty {
            clearConfigurationValidationState()
        }
        pendingSaveRevision += 1
        autoSaveTask?.cancel()
        let targetServiceID = self.serviceID
        autoSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled, let self, self.serviceID == targetServiceID else { return }
                await self.commitChanges()
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Auto-save task error: \(error.localizedDescription)")
            }
        }
    }

    public func commitChanges() async {
        guard !isLoadingServiceDetail else { return }
        guard var srv = service else { return }
        srv.updatedAt = Date()
        self.service = srv

        guard var activeProv = activeProvider else { return }
        activeProv.updatedAt = Date()
        if activeProv.type == .ssh {
            activeProv = ProviderSSHAuth.normalizeForPersistence(activeProv, authType: sshAuthType)
        }
        if activeProv.type == .kubernetes, let kubeVM = kubeConfigVM {
            activeProv.kubeConfigID = kubeVM.selectedKubeConfigID
            activeProv.kubeContext = kubeVM.sanitizedProviderContext(storedProviderContext: activeProv.kubeContext)
        }

        let realPorts = draftPorts.compactMap { item -> ServicePortMapping? in
            let localStr = item.local.trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteStr = item.remote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let local = Int(localStr), let remote = Int(remoteStr), local > 0, remote > 0 else { return nil }
            return ServicePortMapping(
                id: item.id,
                serviceID: self.serviceID,
                providerID: activeProv.id,
                localPort: local,
                remotePort: remote,
                protocolType: "TCP"
            )
        }

        do {
            try await serviceRepository.updateService(srv)
            try await serviceRepository.updateProvider(activeProv.withKubernetesDefaults())
            if portsDraftDirty {
                try await serviceRepository.savePortMappings(realPorts, forService: serviceID, providerID: activeProv.id)
                portsDraftDirty = false
            }

            if let idx = providers.firstIndex(where: { $0.id == activeProv.id }) {
                providers[idx] = activeProv
            }

            lastCommittedRevision = pendingSaveRevision
            postUpdatedNotification()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Failed to commit changes for service \(self.serviceID): \(error.localizedDescription)")
        }
    }
}
