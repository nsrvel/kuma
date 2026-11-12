import Foundation

/// Helper for constructing Service, Provider, and ServicePortMapping models from creation drafts.
public enum CreateServicePayloadBuilder {
    public typealias DraftInputs = CreateServiceDraftInputs

    public static func buildPayload(
        workspaceID: UUID,
        inputs: DraftInputs
    ) throws -> (Service, Provider, [ServicePortMapping]) {
        let serviceID = UUID()
        let service = Service(
            id: serviceID,
            name: inputs.generalDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: inputs.generalDraft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : inputs.generalDraft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            workspaceID: workspaceID,
            isDisabled: inputs.generalDraft.isDisabled
        )

        var sshPasswordPlain: String? = nil
        var sshKeyPathPlain: String? = nil
        var ngrokTokenPlain: String? = nil
        var yamlConfig: String? = nil
        var composeFilePath: String? = nil
        var initialScript: String? = nil
        var initialScriptPath: String? = nil

        if inputs.selectedProvider == .ssh {
            if inputs.sshAuthType == .password && !inputs.sshPassword.isEmpty {
                sshPasswordPlain = inputs.sshPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if inputs.sshAuthType == .key && !inputs.sshKeyPath.isEmpty {
                sshKeyPathPlain = inputs.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if inputs.selectedProvider == .tunnel, inputs.tunnelDraft.engine == .ngrok {
            let trimmedToken = inputs.tunnelDraft.authToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedToken.isEmpty {
                ngrokTokenPlain = trimmedToken
            }
        }

        if inputs.selectedProvider == .docker {
            applyComposeDraft(inputs.dockerDraft, yaml: &yamlConfig, composePath: &composeFilePath, script: &initialScript, scriptPath: &initialScriptPath)
        } else if inputs.selectedProvider == .podman {
            applyComposeDraft(inputs.podmanDraft, yaml: &yamlConfig, composePath: &composeFilePath, script: &initialScript, scriptPath: &initialScriptPath)
        }

        let providerID = UUID()
        let provider = Provider(
            id: providerID,
            serviceID: serviceID,
            type: inputs.selectedProvider,
            kubeConfigID: inputs.selectedProvider == .kubernetes ? inputs.selectedKubeConfigID : nil,
            kubeContext: inputs.selectedProvider == .kubernetes && !inputs.kubeDraft.context.isEmpty ? inputs.kubeDraft.context.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            kubeNamespace: inputs.selectedProvider == .kubernetes && !inputs.kubeDraft.namespace.isEmpty ? inputs.kubeDraft.namespace.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            targetName: inputs.selectedProvider == .kubernetes && !inputs.kubeDraft.targetName.isEmpty ? inputs.kubeDraft.targetName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            kubeTargetType: inputs.kubeDraft.targetType.rawValue,
            usePattern: inputs.kubeDraft.usePattern,
            yamlConfig: yamlConfig,
            composeFilePath: composeFilePath,
            initialScript: initialScript,
            initialScriptPath: initialScriptPath,
            runCommand: inputs.selectedProvider == .shell && !inputs.shellDraft.runCommand.isEmpty ? inputs.shellDraft.runCommand.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            workingDirectory: inputs.selectedProvider == .shell && !inputs.shellDraft.workingDirectory.isEmpty ? inputs.shellDraft.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            sshHost: inputs.selectedProvider == .ssh && !inputs.sshDraft.host.isEmpty ? inputs.sshDraft.host.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            sshUser: inputs.selectedProvider == .ssh && !inputs.sshDraft.user.isEmpty ? inputs.sshDraft.user.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            sshPort: inputs.selectedProvider == .ssh ? Int(inputs.sshDraft.port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22 : nil,
            sshKeyPath: inputs.selectedProvider == .ssh && inputs.sshAuthType == .key ? sshKeyPathPlain : nil,
            sshPassword: inputs.selectedProvider == .ssh && inputs.sshAuthType == .password ? sshPasswordPlain : nil,
            httpCheckUrl: inputs.selectedProvider == .httpCheck && !inputs.healthCheckDraft.url.isEmpty ? healthCheckDraftUrl(inputs.healthCheckDraft.url) : nil,
            httpCheckInterval: inputs.selectedProvider == .httpCheck ? inputs.healthCheckDraft.interval.rawValue : nil,
            tunnelType: inputs.selectedProvider == .tunnel ? inputs.tunnelDraft.engine.rawValue : nil,
            tunnelTargetUrl: inputs.selectedProvider == .tunnel && !inputs.tunnelDraft.targetUrl.isEmpty ? inputs.tunnelDraft.targetUrl.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            ngrokAuthToken: ngrokTokenPlain,
            monitorProcessName: inputs.selectedProvider == .processMonitor && !inputs.monitorDraft.processName.isEmpty ? inputs.monitorDraft.processName.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            monitorInterval: inputs.selectedProvider == .processMonitor ? inputs.monitorDraft.interval.rawValue : nil
        )

        let portMappings: [ServicePortMapping]
        if inputs.selectedProvider == .kubernetes || inputs.selectedProvider == .ssh {
            portMappings = inputs.temporaryPorts.compactMap { item -> ServicePortMapping? in
                guard let local = Int(item.local), let remote = Int(item.remote), local > 0, remote > 0 else { return nil }
                return ServicePortMapping(
                    id: item.id,
                    serviceID: serviceID,
                    providerID: providerID,
                    localPort: local,
                    remotePort: remote
                )
            }
        } else {
            portMappings = []
        }

        return (service, provider, portMappings)
    }

    private static func healthCheckDraftUrl(_ url: String) -> String {
        URLNormalizer.normalize(url) ?? url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isFormValid(inputs: DraftInputs) -> Bool {
        guard !inputs.generalDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if inputs.selectedProvider == .kubernetes || inputs.selectedProvider == .ssh {
            for port in inputs.temporaryPorts {
                let local = port.local.trimmingCharacters(in: .whitespacesAndNewlines)
                let remote = port.remote.trimmingCharacters(in: .whitespacesAndNewlines)
                if !local.isEmpty || !remote.isEmpty {
                    guard let lVal = Int(local), let rVal = Int(remote),
                          lVal > 0, lVal <= 65535,
                          rVal > 0, rVal <= 65535 else {
                        return false
                    }
                }
            }
        }

        switch inputs.selectedProvider {
        case .kubernetes:
            let targetOK = !inputs.kubeDraft.targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let kubeConfigOK = inputs.selectedKubeConfigID != nil
            let contextOK = !inputs.kubeDraft.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCompletePort = inputs.temporaryPorts.contains { item in
                guard let local = Int(item.local.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let remote = Int(item.remote.trimmingCharacters(in: .whitespacesAndNewlines)),
                      local > 0, local <= 65535, remote > 0, remote <= 65535 else { return false }
                return true
            }
            return targetOK && kubeConfigOK && contextOK && hasCompletePort
        case .docker:
            return composeDraftIsValid(inputs.dockerDraft)
        case .podman:
            return composeDraftIsValid(inputs.podmanDraft)
        case .shell:
            return !inputs.shellDraft.runCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ssh:
            return !inputs.sshDraft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !inputs.sshDraft.user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .httpCheck:
            return !inputs.healthCheckDraft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .tunnel:
            return !inputs.tunnelDraft.targetUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .processMonitor:
            return !inputs.monitorDraft.processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
