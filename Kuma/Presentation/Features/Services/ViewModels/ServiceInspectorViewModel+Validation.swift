import Foundation

extension ServiceInspectorViewModel {
    /// Basic UI gate for Start — config rules run only when the user starts.
    public var canStartService: Bool {
        guard !isLoadingServiceDetail else { return false }
        guard let service, !service.isDisabled else { return false }
        return activeProvider != nil
    }

    public func clearConfigurationValidationState() {
        configurationIssues = []
        kubeAsyncValidationMessage = nil
    }

    /// Sync + optional one-shot Kubernetes probe. Updates `configurationIssues` for the banner.
    @discardableResult
    public func validateConfigurationForStart() async -> Bool {
        configurationIssues = recomputeConfigurationIssues(includeKubeAsyncMessage: false)
        if ServiceConfigurationValidator.hasBlockingIssues(configurationIssues) {
            return false
        }
        await refreshKubernetesTargetValidation()
        configurationIssues = recomputeConfigurationIssues(includeKubeAsyncMessage: true)
        return !ServiceConfigurationValidator.hasBlockingIssues(configurationIssues)
    }

    func recomputeConfigurationIssues(includeKubeAsyncMessage: Bool) -> [ConfigurationIssue] {
        guard let service else { return [] }
        let context = makeValidationContext(includeKubeAsyncMessage: includeKubeAsyncMessage)
        return ServiceConfigurationValidator.issues(
            service: service,
            provider: activeProvider,
            context: context
        )
    }

    private func makeValidationContext(includeKubeAsyncMessage: Bool) -> ServiceConfigurationValidationContext {
        let kubeID = kubeConfigVM?.selectedKubeConfigID ?? activeProvider?.kubeConfigID
        let kubeContext = kubeConfigVM?.sanitizedProviderContext(storedProviderContext: activeProvider?.kubeContext)
        return ServiceConfigurationValidationContext(
            sshAuthType: sshAuthType,
            ports: draftPorts,
            kubeConfigID: kubeID,
            kubeContext: kubeContext,
            kubeConnectionError: kubeConfigVM?.connectionError,
            kubeIsConnecting: kubeConfigVM?.isLoadingNamespaces ?? false,
            kubeAsyncMessage: includeKubeAsyncMessage ? kubeAsyncValidationMessage : nil
        )
    }

    func logBlockingConfigurationIssuesToActivity() async {
        let blocking = configurationIssues
            .filter { $0.severity == .blocking }
            .map(\.message)
        guard !blocking.isEmpty else { return }
        await LiveLogSystemEmitter.recordConfigurationIssues(serviceID: serviceID, messages: blocking)
        await LiveLogSystemEmitter.emit(
            serviceID: serviceID,
            message: "Start blocked: fix configuration issues above."
        )
    }

    private func refreshKubernetesTargetValidation() async {
        guard let provider = activeProvider, provider.type == .kubernetes else {
            kubeAsyncValidationMessage = nil
            return
        }

        var probe = provider
        if let kubeConfigVM {
            probe.kubeConfigID = kubeConfigVM.selectedKubeConfigID ?? probe.kubeConfigID
            probe.kubeContext = kubeConfigVM.sanitizedProviderContext(storedProviderContext: probe.kubeContext)
        }

        let syncContext = ServiceConfigurationValidationContext(
            sshAuthType: sshAuthType,
            ports: draftPorts,
            kubeConfigID: probe.kubeConfigID,
            kubeContext: probe.kubeContext,
            kubeConnectionError: kubeConfigVM?.connectionError,
            kubeIsConnecting: kubeConfigVM?.isLoadingNamespaces ?? false,
            kubeAsyncMessage: nil
        )
        guard let service else { return }
        let syncIssues = ServiceConfigurationValidator.issues(service: service, provider: probe, context: syncContext)
        guard !ServiceConfigurationValidator.hasBlockingIssues(syncIssues) else {
            kubeAsyncValidationMessage = nil
            return
        }

        guard let kubectl = await KumaSettingsExecutableResolver.kubectl() else {
            kubeAsyncValidationMessage = ServiceExecutionError.binaryNotFound("kubectl").errorDescription
            return
        }

        do {
            let exec = try await KubeConfigExecutionResolver.resolve(for: probe)
            _ = try await KubeTargetResolver.resolve(provider: probe, kubectlPath: kubectl, exec: exec)
            kubeAsyncValidationMessage = nil
        } catch {
            kubeAsyncValidationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
