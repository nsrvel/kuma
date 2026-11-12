import Foundation
import os

extension ServiceInspectorViewModel {
    public func loadService(id: UUID) async {
        cancelAutoSave()
        self.serviceID = id
        isLoadingServiceDetail = true
        clearConfigurationValidationState()
        defer { isLoadingServiceDetail = false }
        do {
            guard let detail = try await serviceRepository.fetchServiceDetail(id: id) else { return }
            guard self.serviceID == id else { return }

            let srv = detail.service
            let provs = detail.providers
            let portList = detail.portMappings

            self.service = srv
            self.providers = provs.map { $0.withKubernetesDefaults() }
            self.activeProviderID = srv.activeProviderID ?? provs.first?.id

            if portList.isEmpty && (self.activeCategory == .kubernetes || self.activeCategory == .ssh) {
                self.draftPorts = [KumaPortMappingItem()]
            } else {
                self.draftPorts = portList.map {
                    KumaPortMappingItem(id: $0.id, local: "\($0.localPort)", remote: "\($0.remotePort)")
                }
            }

            if let store = stateStore {
                await store.refreshProcessStates(for: [id])
            }

            await syncKubeConfigSelectionFromActiveProvider()
            if let active = activeProvider, active.type == .ssh {
                sshAuthType = ProviderSSHAuth.inferredAuthType(for: active)
            } else if let active = activeProvider, active.type == .kubernetes, let kubeConfigVM {
                kubeConfigVM.testConnection(storedProviderContext: active.kubeContext)
            }
            pendingSaveRevision = 0
            lastCommittedRevision = 0
            portsDraftDirty = false
        } catch {
            Self.logger.error("Failed to load service details for \(id): \(error.localizedDescription)")
        }
    }

    func reloadDraftPortsForActiveProvider() async {
        guard let providerID = activeProviderID else {
            draftPorts = []
            return
        }
        do {
            let portList = try await serviceRepository.fetchPortMappings(forService: serviceID, providerID: providerID)
            if portList.isEmpty && (activeCategory == .kubernetes || activeCategory == .ssh) {
                draftPorts = [KumaPortMappingItem()]
            } else {
                draftPorts = portList.map {
                    KumaPortMappingItem(id: $0.id, local: "\($0.localPort)", remote: "\($0.remotePort)")
                }
            }
            portsDraftDirty = false
        } catch {
            Self.logger.error("Failed to load port mappings for provider \(providerID): \(error.localizedDescription)")
        }
    }

    func syncKubeConfigSelectionFromActiveProvider() async {
        guard let provider = activeProvider, provider.type == .kubernetes else { return }
        if kubeConfigVM == nil {
            kubeConfigVM = KubeConfigViewModel()
        }
        let preferred = provider.kubeConfigID ?? KubeConfig.defaultID
        await kubeConfigVM?.loadConfigs(preferredSelectionID: preferred)
    }
}
