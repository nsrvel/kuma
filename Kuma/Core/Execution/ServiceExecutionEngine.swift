import Foundation
import os

/// Typed errors for service execution
public enum ServiceExecutionError: LocalizedError, Sendable {
    case serviceNotFound(UUID)
    case noActiveProvider(UUID)
    case invalidConfiguration(String)
    case binaryNotFound(String)
    case processFailed(String)
    case portInUse(port: Int, collidingService: String, startingServiceName: String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound(let id):
            return "Service '\(id)' was not found."
        case .noActiveProvider:
            return "No active runner provider is configured for this service."
        case .invalidConfiguration(let msg):
            return "Invalid configuration: \(msg)"
        case .binaryNotFound(let name):
            return "Required binary '\(name)' could not be located on this Mac."
        case .processFailed(let reason):
            return "Execution failed: \(reason)"
        case .portInUse(let port, let collidingService, let startingServiceName):
            return PortConflictMessaging.blockedStartMessage(
                port: port,
                collidingService: collidingService,
                startingServiceName: startingServiceName
            )
        }
    }
}

/// Central orchestrator coordinating modular runners for services.
public final class ServiceExecutionEngine: Sendable {
    public static let shared = ServiceExecutionEngine()
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "ServiceExecutionEngine")

    private let serviceRepository: any ServiceRepositoryProtocol
    private let processRegistry: ProcessRegistry

    private let kubernetesRunner: KubernetesRunner
    private let shellRunner: ShellRunner
    private let containerRunner: ContainerRunner
    private let sshRunner: SSHTunnelRunner
    private let healthCheckRunner: HealthCheckRunner
    private let tunnelRunner: TunnelRunner
    private let processMonitorRunner: ProcessMonitorRunner

    public init(
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository(),
        processRegistry: ProcessRegistry = .shared
    ) {
        self.serviceRepository = serviceRepository
        self.processRegistry = processRegistry
        let processLauncher = ProcessRegistryLauncher(registry: processRegistry)
        self.kubernetesRunner = KubernetesRunner(processLauncher: processLauncher, serviceRepository: serviceRepository)
        self.shellRunner = ShellRunner(processRegistry: processRegistry)
        self.containerRunner = ContainerRunner(processLauncher: processLauncher, composeCLI: LiveComposeCLI())
        self.sshRunner = SSHTunnelRunner(processLauncher: processLauncher, serviceRepository: serviceRepository)
        self.healthCheckRunner = HealthCheckRunner()
        self.tunnelRunner = TunnelRunner(processRegistry: processRegistry)
        self.processMonitorRunner = ProcessMonitorRunner()
    }

    public func start(serviceID: UUID) async throws {
        if await isServiceRunning(serviceID: serviceID) {
            Self.logger.info("Service '\(serviceID)' is already actively running. Skipping rerun.")
            return
        }

        guard let service = try await serviceRepository.fetchService(id: serviceID) else {
            throw ServiceExecutionError.serviceNotFound(serviceID)
        }

        let providers = try await serviceRepository.fetchProviders(forService: serviceID)
        guard let provider = providers.first(where: { $0.id == service.activeProviderID }) ?? providers.first else {
            throw ServiceExecutionError.noActiveProvider(serviceID)
        }

        Self.logger.info("Starting service '\(service.name)' with provider '\(provider.type.rawValue)'")

        await LiveLogSystemEmitter.beginRun(serviceID: serviceID)
        await LiveLogSystemEmitter.emit(
            serviceID: serviceID,
            message: "Starting \"\(service.name)\" (\(provider.type.rawValue))"
        )

        let runner = runner(for: provider.type)
        do {
            try await runner.start(service: service, provider: provider)
            await ExecutionSupervisor.shared.beginReconnectSession(serviceID: serviceID)
        } catch {
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await LiveLogSystemEmitter.emit(serviceID: serviceID, message: "Start failed: \(description)")
            throw error
        }
    }

    public func stop(serviceID: UUID) async {
        await ExecutionSupervisor.shared.stop(serviceID: serviceID)

        let provider = await resolveActiveProvider(for: serviceID)
        if let provider {
            switch provider.type {
            case .docker, .podman:
                await containerRunner.stop(serviceID: serviceID, provider: provider)
            default:
                await runner(for: provider.type).stop(serviceID: serviceID)
            }
        } else {
            await stopAllRunners(serviceID: serviceID)
        }

        if await processRegistry.isRunning(serviceID: serviceID) {
            await processRegistry.stop(serviceID: serviceID)
        }
    }

    func forceReleaseService(serviceID: UUID) async {
        if let provider = await resolveActiveProvider(for: serviceID),
           provider.type == .docker || provider.type == .podman {
            await containerRunner.forceComposeTeardown(serviceID: serviceID, provider: provider)
        }
        containerRunner.forceUnregister(serviceID: serviceID)
        await processRegistry.stop(serviceID: serviceID)
        await ExecutionSupervisor.shared.unregister(serviceID: serviceID)
    }

    func activeProvider(for serviceID: UUID) async -> Provider? {
        await resolveActiveProvider(for: serviceID)
    }

    private func resolveActiveProvider(for serviceID: UUID) async -> Provider? {
        guard let service = try? await serviceRepository.fetchService(id: serviceID) else { return nil }
        guard let providers = try? await serviceRepository.fetchProviders(forService: serviceID) else { return nil }
        return providers.first(where: { $0.id == service.activeProviderID }) ?? providers.first
    }

    private func stopAllRunners(serviceID: UUID) async {
        await kubernetesRunner.stop(serviceID: serviceID)
        await shellRunner.stop(serviceID: serviceID)
        await containerRunner.stop(serviceID: serviceID, provider: nil)
        await sshRunner.stop(serviceID: serviceID)
        await healthCheckRunner.stop(serviceID: serviceID)
        await tunnelRunner.stop(serviceID: serviceID)
        await processMonitorRunner.stop(serviceID: serviceID)
    }

    public func isServiceRunning(serviceID: UUID) async -> Bool {
        await ExecutionSupervisor.shared.isOperational(serviceID: serviceID)
    }

    public func runningServiceIDs(among candidates: Set<UUID>) async -> Set<UUID> {
        await ExecutionSupervisor.shared.runningServiceIDs(among: candidates)
    }

    private func runner(for category: ProviderCategory) -> any ServiceRunnerProtocol {
        switch category {
        case .kubernetes:      return kubernetesRunner
        case .shell:           return shellRunner
        case .docker, .podman: return containerRunner
        case .ssh:             return sshRunner
        case .httpCheck:       return healthCheckRunner
        case .tunnel:          return tunnelRunner
        case .processMonitor:  return processMonitorRunner
        }
    }
}
