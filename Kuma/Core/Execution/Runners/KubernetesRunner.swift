import Foundation
import os

/// Runner responsible for Kubernetes port-forwarding processes using `kubectl`.
/// Ephemeral `kubectl get` / list helpers use `EphemeralCLI`; port-forward is a **managed** process via `ProcessLaunching`.
public final class KubernetesRunner: ServiceRunnerProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "KubernetesRunner")

    private let processLauncher: any ProcessLaunching
    private let serviceRepository: any ServiceRepositoryProtocol

    public nonisolated init(
        processLauncher: any ProcessLaunching = ProcessRegistryLauncher(),
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository()
    ) {
        self.processLauncher = processLauncher
        self.serviceRepository = serviceRepository
    }

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        guard let kubectl = await KumaSettingsExecutableResolver.kubectl() else {
            throw ServiceExecutionError.binaryNotFound("kubectl")
        }

        let portMappings = try await serviceRepository.fetchPortMappings(forService: service.id)
        if portMappings.isEmpty {
            throw ServiceExecutionError.invalidConfiguration("At least one port mapping (Local:Remote) is required for Kubernetes port-forwarding.")
        }

        let execConfig = try await KubeConfigExecutionResolver.resolve(for: provider)
        let namespace = provider.kubeNamespace?.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = execConfig.context?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolved = try await KubeTargetResolver.resolve(
            provider: provider,
            kubectlPath: kubectl,
            exec: execConfig
        )
        KubeLiveTargetDisplay.setResolvedName(resolved.name, for: service.id)
        await LiveLogSystemEmitter.emit(
            serviceID: service.id,
            message: "Resolved target: \(resolved.name)"
        )

        let plan = KubePortForwardPlan.build(
            resolved: resolved,
            exec: execConfig,
            portMappings: portMappings,
            namespace: namespace,
            context: context
        )

        if let adoptedPID = await KubePortForwardAdoption.findAdoptablePID(plan: plan) {
            Self.logger.info(
                "Using existing kubectl port-forward (PID \(adoptedPID, privacy: .public)) for service \(service.id.uuidString, privacy: .public)"
            )
            await LiveLogSystemEmitter.emit(
                serviceID: service.id,
                message: "Adopted existing port-forward (PID \(adoptedPID))"
            )
            await processLauncher.adoptExternalProcess(
                serviceID: service.id,
                serviceName: service.name,
                pid: adoptedPID
            )
            return
        }

        for mapping in portMappings {
            try await LocalPortConflictResolver.shared.ensurePortAvailable(
                port: mapping.localPort,
                startingServiceID: service.id,
                startingServiceName: service.name
            )
        }

        await LiveLogSystemEmitter.emit(serviceID: service.id, message: "Launching kubectl port-forward…")
        _ = try await processLauncher.launch(
            serviceID: service.id,
            serviceName: service.name,
            executable: kubectl,
            arguments: plan.arguments,
            workingDirectory: nil,
            environment: nil,
            onOutput: nil
        )
    }

    public func stop(serviceID: UUID) async {
        await processLauncher.stop(serviceID: serviceID)
        KubeLiveTargetDisplay.clear(serviceID: serviceID)
    }

    public func isRunning(serviceID: UUID) async -> Bool {
        await processLauncher.isRunning(serviceID: serviceID)
    }

}
