import Foundation

/// Narrow surface for runner → process spawn (testable via `RecordingProcessLaunching`).
public protocol ProcessLaunching: Sendable {
    func launch(
        serviceID: UUID,
        serviceName: String,
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> pid_t

    func stop(serviceID: UUID) async

    func isRunning(serviceID: UUID) async -> Bool

    /// Attach an already-running process (e.g. Terminal `kubectl port-forward`) for stop/state tracking.
    func adoptExternalProcess(serviceID: UUID, serviceName: String, pid: pid_t) async
}

/// Forwards to `ProcessRegistry` without making `ProcessLaunching` actor-isolated.
public struct ProcessRegistryLauncher: ProcessLaunching, Sendable {
    private let registry: ProcessRegistry

    public nonisolated init(registry: ProcessRegistry = .shared) {
        self.registry = registry
    }

    public nonisolated func launch(
        serviceID: UUID,
        serviceName: String,
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> pid_t {
        try await registry.launch(
            serviceID: serviceID,
            serviceName: serviceName,
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            onOutput: onOutput
        )
    }

    public nonisolated func stop(serviceID: UUID) async {
        await registry.stop(serviceID: serviceID)
    }

    public nonisolated func isRunning(serviceID: UUID) async -> Bool {
        await registry.isRunning(serviceID: serviceID)
    }

    public nonisolated func adoptExternalProcess(serviceID: UUID, serviceName: String, pid: pid_t) async {
        await registry.adoptExternalProcess(serviceID: serviceID, serviceName: serviceName, pid: pid)
    }
}
