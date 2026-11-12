import Foundation
import os

/// Runner responsible for arbitrary shell script execution using the configured default shell.
public final class ShellRunner: ServiceRunnerProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "ShellRunner")

    private let processRegistry: ProcessRegistry

    public nonisolated init(processRegistry: ProcessRegistry = .shared) {
        self.processRegistry = processRegistry
    }

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        guard let runCommand = provider.runCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !runCommand.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("No shell command specified.")
        }

        var resolvedDir: String? = nil
        if let rawDir = provider.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !rawDir.isEmpty {
            resolvedDir = NSString(string: rawDir).expandingTildeInPath
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: resolvedDir!, isDirectory: &isDir) || !isDir.boolValue {
                throw ServiceExecutionError.invalidConfiguration("Working directory does not exist: '\(rawDir)'")
            }
        }

        let fullPath = await EnvironmentPathResolver.shared.resolvePath()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = fullPath

        let launch = KumaShellLaunchConfiguration.launchSpec(runCommand: runCommand)

        if let resolvedDir {
            await LiveLogSystemEmitter.emit(
                serviceID: service.id,
                message: "Launching shell command (cwd: \(resolvedDir))…"
            )
        } else {
            await LiveLogSystemEmitter.emit(serviceID: service.id, message: "Launching shell command…")
        }

        _ = try await processRegistry.launch(
            serviceID: service.id,
            serviceName: service.name,
            executable: launch.executable,
            arguments: launch.arguments,
            workingDirectory: resolvedDir,
            environment: env,
            onOutput: nil
        )
    }

    public func stop(serviceID: UUID) async {
        await processRegistry.stop(serviceID: serviceID)
    }

    public func isRunning(serviceID: UUID) async -> Bool {
        await processRegistry.isRunning(serviceID: serviceID)
    }
}
