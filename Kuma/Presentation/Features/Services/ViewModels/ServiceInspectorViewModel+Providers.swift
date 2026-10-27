import os
import SwiftUI

extension ServiceInspectorViewModel {
    public func switchProvider(to providerID: UUID) {
        guard providerID != activeProviderID else { return }

        Task {
            let wasRunning = stateStore?.state(for: serviceID).isOperational ?? isRunning
            await flushPendingAutoSave()

            guard var srv = service else { return }

            if wasRunning {
                stateStore?.setExecutionState(.stopping, for: serviceID)
                await ServiceStopSupport.stopOffMainActor(serviceID: serviceID, stateStore: stateStore)
            }

            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                self.activeProviderID = providerID
                srv.activeProviderID = providerID
                srv.updatedAt = Date()
                self.service = srv
            }

            do {
                try await serviceRepository.updateService(srv)
                await reloadDraftPortsForActiveProvider()
                await syncKubeConfigSelectionFromActiveProvider()
                if let active = activeProvider, active.type == .ssh {
                    sshAuthType = ProviderSSHAuth.inferredAuthType(for: active)
                }
                postUpdatedNotification()

                if wasRunning {
                    guard await validateConfigurationForStart() else { return }
                    configurationIssues = []
                    stateStore?.setExecutionState(.starting, for: serviceID)
                    try await ServiceExecutionEngine.shared.start(serviceID: serviceID)
                    await ServiceExecutionStateSync.applyAfterSuccessfulStart(
                        serviceID: serviceID,
                        stateStore: stateStore
                    )
                }
            } catch {
                Self.logger.error("Failed to switch active provider for service \(srv.id): \(error.localizedDescription)")
                if wasRunning, error is ServiceExecutionError {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    stateStore?.setLastFailureMessage(message, for: serviceID)
                    stateStore?.setExecutionState(.crashed(exitCode: 1), for: serviceID)
                } else {
                    stateStore?.clearStoppingIfStillPending(for: serviceID)
                }
                ServiceStartFailurePresenter.present(error: error, serviceName: srv.name)
            }
        }
    }

    public func addProvider(_ provider: Provider) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            self.providers.append(provider)
            self.activeProviderID = provider.id
            if var srv = self.service {
                srv.activeProviderID = provider.id
                srv.updatedAt = Date()
                self.service = srv
            }
        }

        if provider.type == .kubernetes && kubeConfigVM == nil {
            self.kubeConfigVM = KubeConfigViewModel()
        }

        if provider.type == .kubernetes {
            Task { await syncKubeConfigSelectionFromActiveProvider() }
        }

        if provider.type == .kubernetes || provider.type == .ssh {
            draftPorts = [KumaPortMappingItem()]
        } else {
            draftPorts = []
        }
        portsDraftDirty = false

        Task {
            do {
                try await serviceRepository.insertProvider(provider)
                if let srv = self.service {
                    try await serviceRepository.updateService(srv)
                }
                postUpdatedNotification()
            } catch {
                Self.logger.error("Failed to add provider: \(error.localizedDescription)")
            }
        }
    }

    public func updateProviderDirectly(_ provider: Provider) {
        Task {
            do {
                try await serviceRepository.updateProvider(provider)
                if let idx = self.providers.firstIndex(where: { $0.id == provider.id }) {
                    self.providers[idx] = provider
                }
                postUpdatedNotification()
            } catch {
                Self.logger.error("Failed to update provider \(provider.id): \(error.localizedDescription)")
            }
        }
    }

    public func deleteProvider(_ provider: Provider) {
        Task {
            do {
                try await serviceRepository.deleteProvider(id: provider.id)
                self.providers.removeAll(where: { $0.id == provider.id })
                if self.activeProviderID == provider.id {
                    self.activeProviderID = self.providers.first?.id
                    if var srv = self.service {
                        srv.activeProviderID = self.activeProviderID
                        try await self.serviceRepository.updateService(srv)
                        self.service = srv
                    }
                    await reloadDraftPortsForActiveProvider()
                    portsDraftDirty = false
                }
                postUpdatedNotification()
            } catch {
                Self.logger.error("Failed to delete provider \(provider.id): \(error.localizedDescription)")
            }
        }
    }

    public func toggleStarred() {
        guard var srv = service else { return }
        srv.isStarred.toggle()
        srv.updatedAt = Date()
        self.service = srv

        Task {
            do {
                _ = try await serviceRepository.toggleStarred(serviceID: serviceID)
                postUpdatedNotification()
            } catch {
                Self.logger.error("Failed to toggle starred for \(self.serviceID): \(error.localizedDescription)")
            }
        }
    }

    public func toggleDisabled(_ isDisabled: Bool) {
        guard var srv = service else { return }
        srv.isDisabled = isDisabled
        srv.updatedAt = Date()
        self.service = srv

        Task {
            do {
                try await serviceRepository.updateService(srv)
                postUpdatedNotification()
            } catch {
                Self.logger.error("Failed to toggle disabled state for \(self.serviceID): \(error.localizedDescription)")
            }
        }
    }

    public func deleteService() {
        Task {
            do {
                try await serviceRepository.deleteService(id: serviceID)
                NotificationCenter.default.post(name: .kumaServiceDeleted, object: serviceID)
            } catch {
                Self.logger.error("Failed to delete service \(self.serviceID): \(error.localizedDescription)")
            }
        }
    }
}
