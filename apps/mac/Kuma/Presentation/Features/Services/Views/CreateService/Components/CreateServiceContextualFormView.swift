import SwiftUI

/// Contextual provider form sections switcher for CreateServiceFillDetailsStepView.
public struct CreateServiceContextualFormView: View {
    public let selectedProvider: ProviderCategory
    @Binding public var kubeDraft: ServiceKubernetesDraft
    public var kubeConfigVM: KubeConfigViewModel
    @Binding public var dockerDraft: ServiceComposeDraft
    @Binding public var podmanDraft: ServiceComposeDraft
    @Binding public var shellDraft: ServiceShellDraft
    @Binding public var sshDraft: ServiceSSHDraft
    @Binding public var sshAuthType: SSHAuthType
    @Binding public var sshKeyPath: String
    @Binding public var sshPassword: String
    @Binding public var healthCheckDraft: ServiceHealthCheckDraft
    @Binding public var tunnelDraft: ServiceTunnelDraft
    @Binding public var monitorDraft: ServiceProcessMonitorDraft

    public init(
        selectedProvider: ProviderCategory,
        kubeDraft: Binding<ServiceKubernetesDraft>,
        kubeConfigVM: KubeConfigViewModel,
        dockerDraft: Binding<ServiceComposeDraft>,
        podmanDraft: Binding<ServiceComposeDraft>,
        shellDraft: Binding<ServiceShellDraft>,
        sshDraft: Binding<ServiceSSHDraft>,
        sshAuthType: Binding<SSHAuthType>,
        sshKeyPath: Binding<String>,
        sshPassword: Binding<String>,
        healthCheckDraft: Binding<ServiceHealthCheckDraft>,
        tunnelDraft: Binding<ServiceTunnelDraft>,
        monitorDraft: Binding<ServiceProcessMonitorDraft>
    ) {
        self.selectedProvider = selectedProvider
        self._kubeDraft = kubeDraft
        self.kubeConfigVM = kubeConfigVM
        self._dockerDraft = dockerDraft
        self._podmanDraft = podmanDraft
        self._shellDraft = shellDraft
        self._sshDraft = sshDraft
        self._sshAuthType = sshAuthType
        self._sshKeyPath = sshKeyPath
        self._sshPassword = sshPassword
        self._healthCheckDraft = healthCheckDraft
        self._tunnelDraft = tunnelDraft
        self._monitorDraft = monitorDraft
    }

    public var body: some View {
        switch selectedProvider {
        case .kubernetes:
            KubeConfigConnectionView(
                viewModel: kubeConfigVM,
                isLocked: false,
                contextToTest: kubeDraft.context,
                onConfigChanged: {
                    let stored = kubeDraft.context.isEmpty ? nil : kubeDraft.context
                    if let sanitized = kubeConfigVM.sanitizedProviderContext(storedProviderContext: stored) {
                        kubeDraft.context = sanitized
                    }
                    kubeConfigVM.testConnection(storedProviderContext: kubeDraft.context.isEmpty ? nil : kubeDraft.context)
                }
            )

            KumaFormSection(icon: "network", title: "Cluster Connection") {
                KubeConnectionSettingsView(
                    kubeNamespace: $kubeDraft.namespace,
                    kubeContext: $kubeDraft.context,
                    availableContexts: kubeConfigVM.availableContexts
                )
                .onChange(of: kubeDraft.context) { _, newContext in
                    kubeConfigVM.testConnection(storedProviderContext: newContext)
                }
            }
            .onChange(of: kubeConfigVM.availableContexts, initial: true) { _, contexts in
                if let active = kubeConfigVM.activeContextName, contexts.contains(active) {
                    kubeDraft.context = active
                } else if let first = contexts.first, !contexts.contains(kubeDraft.context) {
                    kubeDraft.context = first
                }
            }

            KumaFormSection(icon: "scope", title: "Target Resource") {
                KubeTargetSettingsView(
                    targetName: $kubeDraft.targetName,
                    targetType: $kubeDraft.targetType,
                    usePattern: $kubeDraft.usePattern
                )
            }

        case .docker:
            CreateServiceComposeConfigurationSection(
                isPodman: false,
                yamlConfig: $dockerDraft.yamlConfig,
                composeFilePath: $dockerDraft.composeFilePath,
                initialScript: $dockerDraft.initialScript,
                initialScriptPath: $dockerDraft.initialScriptPath
            )

        case .podman:
            CreateServiceComposeConfigurationSection(
                isPodman: true,
                yamlConfig: $podmanDraft.yamlConfig,
                composeFilePath: $podmanDraft.composeFilePath,
                initialScript: $podmanDraft.initialScript,
                initialScriptPath: $podmanDraft.initialScriptPath
            )

        case .shell:
            KumaFormSection(icon: "terminal.fill", title: "Shell Command") {
                ShellScriptSettingsView(runCommand: $shellDraft.runCommand, workingDirectory: $shellDraft.workingDirectory)
            }

        case .ssh:
            KumaFormSection(icon: "network", title: "SSH Connection") {
                SSHSettingsView(
                    sshHost: $sshDraft.host,
                    sshPort: $sshDraft.port,
                    sshUser: $sshDraft.user,
                    authType: $sshAuthType,
                    sshKeyPath: $sshKeyPath,
                    sshPassword: $sshPassword
                )
            }

        case .httpCheck:
            KumaFormSection(icon: "heart.text.square.fill", title: "Health Check") {
                HealthCheckSettingsView(httpCheckUrl: $healthCheckDraft.url, checkInterval: $healthCheckDraft.interval)
            }

        case .tunnel:
            KumaFormSection(icon: "cloud.bolt.fill", title: "Public Tunnel") {
                TunnelSettingsView(tunnelType: $tunnelDraft.engine, tunnelTargetUrl: $tunnelDraft.targetUrl, ngrokAuthToken: $tunnelDraft.authToken)
            }

        case .processMonitor:
            KumaFormSection(icon: "cpu.fill", title: "Process Monitor") {
                ProcessMonitorSettingsView(monitorProcessName: $monitorDraft.processName, monitorInterval: $monitorDraft.interval)
            }
        }
    }
}
