import Foundation

/// Inputs bundle for building creation payloads and verifying form validity.
public struct CreateServiceDraftInputs: Sendable {
    public let selectedProvider: ProviderCategory
    public let generalDraft: ServiceGeneralDraft
    public let kubeDraft: ServiceKubernetesDraft
    public let selectedKubeConfigID: UUID?
    public let dockerDraft: ServiceComposeDraft
    public let podmanDraft: ServiceComposeDraft
    public let shellDraft: ServiceShellDraft
    public let sshDraft: ServiceSSHDraft
    public let sshAuthType: SSHAuthType
    public let sshKeyPath: String
    public let sshPassword: String
    public let healthCheckDraft: ServiceHealthCheckDraft
    public let tunnelDraft: ServiceTunnelDraft
    public let monitorDraft: ServiceProcessMonitorDraft
    public let temporaryPorts: [KumaPortMappingItem]

    public init(
        selectedProvider: ProviderCategory,
        generalDraft: ServiceGeneralDraft,
        kubeDraft: ServiceKubernetesDraft,
        selectedKubeConfigID: UUID?,
        dockerDraft: ServiceComposeDraft,
        podmanDraft: ServiceComposeDraft,
        shellDraft: ServiceShellDraft,
        sshDraft: ServiceSSHDraft,
        sshAuthType: SSHAuthType,
        sshKeyPath: String,
        sshPassword: String,
        healthCheckDraft: ServiceHealthCheckDraft,
        tunnelDraft: ServiceTunnelDraft,
        monitorDraft: ServiceProcessMonitorDraft,
        temporaryPorts: [KumaPortMappingItem]
    ) {
        self.selectedProvider = selectedProvider
        self.generalDraft = generalDraft
        self.kubeDraft = kubeDraft
        self.selectedKubeConfigID = selectedKubeConfigID
        self.dockerDraft = dockerDraft
        self.podmanDraft = podmanDraft
        self.shellDraft = shellDraft
        self.sshDraft = sshDraft
        self.sshAuthType = sshAuthType
        self.sshKeyPath = sshKeyPath
        self.sshPassword = sshPassword
        self.healthCheckDraft = healthCheckDraft
        self.tunnelDraft = tunnelDraft
        self.monitorDraft = monitorDraft
        self.temporaryPorts = temporaryPorts
    }
}
