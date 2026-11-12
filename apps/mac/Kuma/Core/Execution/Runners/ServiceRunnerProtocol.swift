import Foundation

/// Unified protocol for runner engines powering specific provider categories in Kuma.
///
/// Subprocess policy:
/// - **Managed** (`ProcessLaunching` / `ProcessRegistry`): one long-lived process per `serviceID` (Shell, SSH, Tunnel, K8s port-forward).
/// - **Ephemeral** (`EphemeralCLI`, `ComposeCLI`): short-lived CLI; never registered (compose up/down, kubectl preflight/list).
/// - **Task polling** (Health Check, Process Monitor): in-memory task set; `isRunning` is not tied to `ProcessRegistry`.
public protocol ServiceRunnerProtocol: Sendable {
    /// Starts execution of a service using the specified provider configuration.
    func start(
        service: Service,
        provider: Provider
    ) async throws

    /// Stops any running process or background polling task associated with the service.
    func stop(serviceID: UUID) async

    /// Queries whether the service is currently running under this runner.
    func isRunning(serviceID: UUID) async -> Bool
}
