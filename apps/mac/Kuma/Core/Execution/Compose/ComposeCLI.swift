import Foundation

public protocol ComposeCLIExecuting: Sendable {
    func run(
        context: ComposeStackContext,
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> Int32
}

public struct LiveComposeCLI: ComposeCLIExecuting {
    public init() {}
    public func run(
        context: ComposeStackContext,
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> Int32 {
        try await ComposeCLI.run(context: context, arguments: arguments, timeout: timeout)
    }
}

/// Runs short-lived `docker|podman compose` subprocesses outside `ProcessRegistry` (avoids false crash/stop signals after `up -d`).
enum ComposeCLI {
    struct RunResult: Sendable {
        let exitCode: Int32
        let output: String
    }

    static func runDetailed(
        context: ComposeStackContext,
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> RunResult {
        let result = try await EphemeralCLI.run(
            executablePath: context.binaryPath,
            arguments: arguments,
            workingDirectory: context.workingDirectory,
            timeout: timeout,
            stdio: .merged
        )
        return RunResult(exitCode: result.terminationStatus, output: result.stderr)
    }

    @discardableResult
    static func run(
        context: ComposeStackContext,
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> Int32 {
        try await runDetailed(context: context, arguments: arguments, timeout: timeout).exitCode
    }
}
