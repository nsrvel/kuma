import Foundation

/// HTTP health checks — registered with `ExecutionSupervisor` poller (no per-service Task).
public final class HealthCheckRunner: ServiceRunnerProtocol, @unchecked Sendable {
    public nonisolated init() {}

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        guard let rawUrl = provider.httpCheckUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUrl.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("Health Check Target URL is not specified.")
        }
        guard let normalizedUrlString = URLNormalizer.normalize(rawUrl),
              let targetURL = URL(string: normalizedUrlString) else {
            throw ServiceExecutionError.invalidConfiguration("Invalid Health Check URL: '\(rawUrl)'.")
        }
        let intervalSeconds = max(provider.httpCheckInterval ?? 10, 3)
        await ExecutionSupervisor.shared.register(
            .pollerHealth(
                serviceID: service.id,
                serviceName: service.name,
                url: targetURL,
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
