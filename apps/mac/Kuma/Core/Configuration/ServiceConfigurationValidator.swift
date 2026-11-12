import Foundation

public struct ServiceConfigurationValidationContext: Sendable {
    public var sshAuthType: SSHAuthType
    public var ports: [KumaPortMappingItem]
    public var kubeConfigID: UUID?
    public var kubeContext: String?
    public var kubeConnectionError: String?
    public var kubeIsConnecting: Bool
    public var kubeAsyncMessage: String?

    public init(
        sshAuthType: SSHAuthType = .key,
        ports: [KumaPortMappingItem] = [],
        kubeConfigID: UUID? = nil,
        kubeContext: String? = nil,
        kubeConnectionError: String? = nil,
        kubeIsConnecting: Bool = false,
        kubeAsyncMessage: String? = nil
    ) {
        self.sshAuthType = sshAuthType
        self.ports = ports
        self.kubeConfigID = kubeConfigID
        self.kubeContext = kubeContext
        self.kubeConnectionError = kubeConnectionError
        self.kubeIsConnecting = kubeIsConnecting
        self.kubeAsyncMessage = kubeAsyncMessage
    }
}

/// Sync (+ optional precomputed async) inspector configuration checks shared with execution preflight.
public enum ServiceConfigurationValidator {
    public static func issues(
        service: Service,
        provider: Provider?,
        context: ServiceConfigurationValidationContext
    ) -> [ConfigurationIssue] {
        guard !service.isDisabled else { return [] }
        guard let provider else {
            return [ConfigurationIssue(code: "provider.missing", message: "Add a provider before starting this service.")]
        }

        var issues: [ConfigurationIssue] = []
        issues.append(contentsOf: portIssues(ports: context.ports, requiredFor: provider.type))

        switch provider.type {
        case .kubernetes:
            issues.append(contentsOf: kubernetesIssues(provider: provider, context: context))
        case .docker, .podman:
            issues.append(contentsOf: composeIssues(service: service, provider: provider))
        case .shell:
            issues.append(contentsOf: shellIssues(provider: provider))
        case .ssh:
            issues.append(contentsOf: sshIssues(provider: provider, context: context))
        case .httpCheck:
            issues.append(contentsOf: healthCheckIssues(provider: provider))
        case .tunnel:
            issues.append(contentsOf: tunnelIssues(provider: provider))
        case .processMonitor:
            issues.append(contentsOf: processMonitorIssues(provider: provider))
        }

        if let asyncMsg = context.kubeAsyncMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !asyncMsg.isEmpty,
           provider.type == .kubernetes {
            issues.append(ConfigurationIssue(code: "k8s.target_resolve", message: asyncMsg))
        }

        return issues
    }

    public static func hasBlockingIssues(_ issues: [ConfigurationIssue]) -> Bool {
        issues.contains { $0.severity == .blocking }
    }

    // MARK: - Ports

    private static func portIssues(ports: [KumaPortMappingItem], requiredFor type: ProviderCategory) -> [ConfigurationIssue] {
        guard type == .kubernetes || type == .ssh else { return [] }

        let trimmedRows = ports.map { row in
            (
                local: row.local.trimmingCharacters(in: .whitespacesAndNewlines),
                remote: row.remote.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        var issues: [ConfigurationIssue] = []
        for (index, row) in trimmedRows.enumerated() {
            let bothEmpty = row.local.isEmpty && row.remote.isEmpty
            if bothEmpty { continue }
            if !isCompletePortRow(local: row.local, remote: row.remote) {
                issues.append(ConfigurationIssue(
                    code: "ports.invalid_row_\(index)",
                    message: "Port row \(index + 1): enter local and remote ports (1–65535)."
                ))
            }
        }

        let completeLocals = trimmedRows.compactMap { row -> Int? in
            guard isCompletePortRow(local: row.local, remote: row.remote), let value = Int(row.local) else { return nil }
            return value
        }
        if completeLocals.isEmpty {
            issues.append(ConfigurationIssue(
                code: "ports.required",
                message: "Add at least one complete port mapping (local and remote)."
            ))
            return issues
        }

        let unique = Set(completeLocals)
        if unique.count != completeLocals.count {
            issues.append(ConfigurationIssue(code: "ports.duplicate_local", message: "Each local port must be unique."))
        }
        return issues
    }

    private static func isCompletePortRow(local: String, remote: String) -> Bool {
        guard let localVal = Int(local), let remoteVal = Int(remote) else { return false }
        return localVal > 0 && localVal <= 65535 && remoteVal > 0 && remoteVal <= 65535
    }

    // MARK: - Kubernetes

    private static func kubernetesIssues(
        provider: Provider,
        context: ServiceConfigurationValidationContext
    ) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []

        if context.kubeConfigID == nil {
            issues.append(ConfigurationIssue(code: "k8s.kubeconfig", message: "Select a kubeconfig."))
        }

        let ctx = context.kubeContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ctx.isEmpty {
            issues.append(ConfigurationIssue(code: "k8s.context", message: "Select a Kubernetes context."))
        }

        let target = provider.targetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if target.isEmpty {
            issues.append(ConfigurationIssue(code: "k8s.target", message: "Enter a target name (pod, service, or pattern)."))
        }

        if context.kubeIsConnecting {
            return issues
        }

        if let connectionError = context.kubeConnectionError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !connectionError.isEmpty {
            issues.append(ConfigurationIssue(code: "k8s.unreachable", message: connectionError))
        }

        return issues
    }

    // MARK: - Compose

    private static func composeIssues(service: Service, provider: Provider) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        let hasPath = !(provider.composeFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasYAML = !(provider.yamlConfig?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasPath && !hasYAML {
            issues.append(ConfigurationIssue(
                code: "compose.missing",
                message: "Choose a compose file or paste compose YAML."
            ))
            return issues
        }

        do {
            _ = try ComposeStackResolver.resolve(
                service: service,
                provider: provider,
                configuredWorkingDirectory: ComposeStackResolver.configuredWorkingDirectory(from: provider)
            )
        } catch let error as ServiceExecutionError {
            issues.append(ConfigurationIssue(code: "compose.invalid", message: error.errorDescription ?? "Compose configuration is invalid."))
        } catch {
            issues.append(ConfigurationIssue(code: "compose.invalid", message: error.localizedDescription))
        }

        if let rawPath = provider.initialScriptPath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || isDir.boolValue {
                issues.append(ConfigurationIssue(code: "compose.startup_script", message: "Startup script file not found: \(rawPath)"))
            }
        }

        if let rawDir = provider.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !rawDir.isEmpty {
            let expanded = NSString(string: rawDir).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                issues.append(ConfigurationIssue(code: "compose.working_dir", message: "Working directory does not exist: \(rawDir)"))
            }
        }

        return issues
    }

    // MARK: - Shell

    private static func shellIssues(provider: Provider) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        let command = provider.runCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if command.isEmpty {
            issues.append(ConfigurationIssue(code: "shell.command", message: "Enter a shell command to run."))
        }
        if let rawDir = provider.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !rawDir.isEmpty {
            let expanded = NSString(string: rawDir).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) || !isDir.boolValue {
                issues.append(ConfigurationIssue(code: "shell.working_dir", message: "Working directory does not exist: \(rawDir)"))
            }
        }
        return issues
    }

    // MARK: - SSH

    private static func sshIssues(provider: Provider, context: ServiceConfigurationValidationContext) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        let host = provider.sshHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if host.isEmpty {
            issues.append(ConfigurationIssue(code: "ssh.host", message: "SSH host is required."))
        }

        let user = provider.sshUser?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if user.isEmpty {
            issues.append(ConfigurationIssue(code: "ssh.user", message: "SSH user is required."))
        }

        switch context.sshAuthType {
        case .password:
            let pass = provider.sshPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pass.isEmpty {
                issues.append(ConfigurationIssue(code: "ssh.password", message: "SSH password is required."))
            }
        case .key:
            let keyPath = provider.sshKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if keyPath.isEmpty {
                issues.append(ConfigurationIssue(code: "ssh.key", message: "SSH private key path is required."))
            } else {
                let expanded = NSString(string: keyPath).expandingTildeInPath
                if !FileManager.default.fileExists(atPath: expanded) {
                    issues.append(ConfigurationIssue(code: "ssh.key_missing", message: "SSH private key file not found: \(keyPath)"))
                }
            }
        }
        return issues
    }

    // MARK: - Health / tunnel / monitor

    private static func healthCheckIssues(provider: Provider) -> [ConfigurationIssue] {
        let raw = provider.httpCheckUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            return [ConfigurationIssue(code: "health.url", message: "Health check URL is required.")]
        }
        if URLNormalizer.normalize(raw) == nil {
            return [ConfigurationIssue(code: "health.url_invalid", message: "Health check URL is not valid.")]
        }
        return []
    }

    private static func tunnelIssues(provider: Provider) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        let target = provider.tunnelTargetUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if target.isEmpty {
            issues.append(ConfigurationIssue(code: "tunnel.target", message: "Tunnel target (port or URL) is required."))
        }
        let engine = provider.tunnelType?.lowercased() ?? "cloudflare"
        if engine == "ngrok" {
            let token = provider.ngrokAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if token.isEmpty {
                issues.append(ConfigurationIssue(code: "tunnel.ngrok_token", message: "Ngrok auth token is required."))
            }
        }
        return issues
    }

    private static func processMonitorIssues(provider: Provider) -> [ConfigurationIssue] {
        let name = provider.monitorProcessName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            return [ConfigurationIssue(code: "monitor.process", message: "Process name to monitor is required.")]
        }
        return []
    }
}
