import Foundation

/// Process monitor — registered with `ExecutionSupervisor` poller (batched `ps`).
public final class ProcessMonitorRunner: ServiceRunnerProtocol, @unchecked Sendable {
    public nonisolated init() {}

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        guard let processName = provider.monitorProcessName?.trimmingCharacters(in: .whitespacesAndNewlines), !processName.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("Process name to monitor is required.")
        }
        let intervalSeconds = max(provider.monitorInterval ?? 5, 2)
        await ExecutionSupervisor.shared.register(
            .pollerProcess(
                serviceID: service.id,
                serviceName: service.name,
                processName: processName,
                intervalSeconds: intervalSeconds
            )
        )
    }

    public func stop(serviceID: UUID) async {
        await ExecutionSupervisor.shared.unregister(serviceID: serviceID)
    }

    public func isRunning(serviceID: UUID) async -> Bool {
        if let record = await ExecutionSupervisor.shared.record(for: serviceID) {
            return record.mode == .poller && record.executionState.isOperational
        }
        return false
    }

    public func activeServiceIDs() -> Set<UUID> { [] }
}
