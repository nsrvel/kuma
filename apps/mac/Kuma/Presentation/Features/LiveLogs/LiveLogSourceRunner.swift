import Foundation

/// Tails workload output (kubectl logs, compose logs, process spool).
/// Not used by the inspector system-log panel; reserved for provider-specific workload windows.
enum LiveLogSourceRunner {
    static func run(
        serviceID: UUID,
        service: Service,
        provider: Provider,
        onChunk: @escaping @Sendable (String) -> Void
    ) async {
        switch provider.type {
        case .kubernetes:
            await tailKube(service: service, provider: provider, onChunk: onChunk)
        case .docker, .podman:
            await tailCompose(serviceID: serviceID, provider: provider, onChunk: onChunk)
        case .shell, .ssh, .tunnel:
            await tailSpool(serviceID: serviceID, onChunk: onChunk)
        case .httpCheck, .processMonitor:
            await idleUntilCancelled()
        }
    }

    private static func idleUntilCancelled() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private static func tailSpool(serviceID: UUID, onChunk: @escaping @Sendable (String) -> Void) async {
        let path = RunSpool.url(for: serviceID).path
        var offset: UInt64 = 0
        while !Task.isCancelled {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               data.count > Int(offset) {
                let slice = data.subdata(in: Int(offset)..<data.count)
                offset = UInt64(data.count)
                if let text = String(data: slice, encoding: .utf8) {
                    onChunk(text)
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private static func tailCompose(serviceID: UUID, provider: Provider, onChunk: @escaping @Sendable (String) -> Void) async {
        guard let binary = provider.type == .docker
            ? await KumaSettingsExecutableResolver.docker()
            : await KumaSettingsExecutableResolver.podman() else { return }
        let stub = Service(id: serviceID, name: "logs")
        guard let context = try? ComposeStackResolver.makeContext(service: stub, provider: provider, binaryPath: binary) else { return }
        let args = ["compose", "-p", context.projectName, "-f", context.composeFilePath, "logs", "-f", "--tail=200"]
        await streamProcess(executable: binary, arguments: args, workingDirectory: context.workingDirectory, onChunk: onChunk)
    }

    private static func tailKube(service: Service, provider: Provider, onChunk: @escaping @Sendable (String) -> Void) async {
        guard let kubectl = await KumaSettingsExecutableResolver.kubectl() else { return }
        guard let exec = try? await KubeConfigExecutionResolver.resolve(for: provider) else { return }
        guard let resolved = try? await KubeTargetResolver.resolve(
            provider: provider,
            kubectlPath: kubectl,
            exec: exec
        ) else { return }

        var args = ["logs", "-f", "--tail=200", resolved.kubectlReference]
        if let path = exec.kubeconfigPath, !path.isEmpty {
            args.insert(contentsOf: ["--kubeconfig", path], at: 0)
        }
        if let ctx = exec.context?.trimmingCharacters(in: .whitespacesAndNewlines), !ctx.isEmpty {
            args.append(contentsOf: ["--context", ctx])
        }
        if let ns = provider.kubeNamespace?.trimmingCharacters(in: .whitespacesAndNewlines), !ns.isEmpty {
            args.append(contentsOf: ["-n", ns])
        }
        await streamProcess(executable: kubectl, arguments: args, workingDirectory: nil, onChunk: onChunk)
    }

    private static func streamProcess(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onChunk(text)
        }
        do {
            try process.run()
            await SubprocessWait.waitForExit(of: process)
        } catch {}
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}
