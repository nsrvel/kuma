import Foundation

struct KubeResolvedTarget: Sendable {
    nonisolated let kind: String
    nonisolated let name: String

    nonisolated var kubectlReference: String { "\(kind)/\(name)" }

    nonisolated init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// Resolves `kubectl <kind>/<name>` for port-forward, logs, and related commands.
enum KubeTargetResolver {
    static func resolve(
        provider: Provider,
        kubectlPath: String,
        exec: KubeExecCredentials,
        log: @Sendable (String) async -> Void = { _ in }
    ) async throws -> KubeResolvedTarget {
        guard let targetName = provider.targetName?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("Target resource name is required (e.g. my-app-service or pod pattern).")
        }

        let kubeTarget = KubeTargetType(rawValue: provider.kubeTargetType ?? "") ?? .pod
        let namespace = provider.kubeNamespace?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedName: String
        if shouldDiscoverResources(provider: provider, kubeTarget: kubeTarget, targetName: targetName) {
            resolvedName = try await discoverMatchingName(
                kubectlPath: kubectlPath,
                targetType: kubeTarget,
                targetPattern: targetName,
                namespace: namespace,
                context: exec.context?.trimmingCharacters(in: .whitespacesAndNewlines),
                kubeconfigPath: exec.kubeconfigPath,
                log: log
            )
        } else {
            resolvedName = targetName
        }

        return KubeResolvedTarget(kind: kubeTarget.portForwardKind, name: resolvedName)
    }

    /// Pattern matching on, or Pod target with a deployment-style name (resolve to a replica pod).
    private static func shouldDiscoverResources(provider: Provider, kubeTarget: KubeTargetType, targetName: String) -> Bool {
        if provider.usePattern ?? true { return true }
        if kubeTarget == .pod && KubeTargetNamingHints.looksLikeStableWorkloadName(targetName) {
            return true
        }
        return false
    }

    private static func discoverMatchingName(
        kubectlPath: String,
        targetType: KubeTargetType,
        targetPattern: String,
        namespace: String?,
        context: String?,
        kubeconfigPath: String?,
        log: @Sendable (String) async -> Void
    ) async throws -> String {
        let nsLabel = namespace?.isEmpty == false ? namespace! : "default"
        await log("Discovering \(targetType.displayLabel) in namespace '\(nsLabel)' for '\(targetPattern)'...")

        var listArgs = ["get", targetType.listResource]
        if targetType == .pod {
            listArgs.append(contentsOf: ["--field-selector=status.phase=Running", "-o", "name"])
        } else {
            listArgs.append(contentsOf: ["-o", "name"])
        }

        if let kubeconfigPath, !kubeconfigPath.isEmpty {
            listArgs.append("--kubeconfig")
            listArgs.append(kubeconfigPath)
        }

        if let namespace, !namespace.isEmpty {
            listArgs.append("-n")
            listArgs.append(namespace)
        }

        if let context, !context.isEmpty {
            listArgs.append("--context")
            listArgs.append(context)
        }

        let result = try await EphemeralCLI.run(
            executablePath: kubectlPath,
            arguments: listArgs,
            timeout: KumaExecutionTimeouts.kubectlSubcommand,
            stdio: .captureSeparated
        )

        let resourceNames = parseResourceNames(from: result.stdout)

        if resourceNames.isEmpty {
            let errMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !errMsg.isEmpty {
                throw ServiceExecutionError.processFailed("Kubectl \(targetType.listResource) discovery error: \(errMsg)")
            }
            let emptyHint = targetType == .pod ? "No running pods found" : "No \(targetType.listResource) found"
            throw ServiceExecutionError.processFailed("\(emptyHint) in namespace '\(nsLabel)'.")
        }

        let allowPodReplicaPrefix = targetType == .pod
        guard let matched = KubeTargetNameMatcher.firstMatch(
            pattern: targetPattern,
            in: resourceNames,
            allowPodReplicaPrefix: allowPodReplicaPrefix
        ) else {
            throw ServiceExecutionError.processFailed(
                "Found \(resourceNames.count) \(targetType.listResource) in '\(nsLabel)', but none matched '\(targetPattern)'. Examples: \(resourceNames.prefix(3).joined(separator: ", "))"
            )
        }

        await log("Using \(targetType.portForwardKind)/\(matched) for port-forward.")
        return matched
    }

    private static func parseResourceNames(from stdout: String) -> [String] {
        stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                guard let slash = line.lastIndex(of: "/") else { return line }
                return String(line[line.index(after: slash)...])
            }
            .sorted()
    }
}
