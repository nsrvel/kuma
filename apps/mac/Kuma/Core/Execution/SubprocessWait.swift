import Foundation
import Darwin

/// Bounded waits for subprocess teardown (PROC-04).
enum KumaExecutionTimeouts: Sendable {
    /// Max wait for `docker|podman compose down` during service stop.
    static let composeDown: TimeInterval = 45
    /// Max wait for pre-compose startup script (inline or file).
    static let initialScript: TimeInterval = 120
    /// Max wall time for full `ServiceExecutionEngine.stop` before forcing `ProcessRegistry` teardown.
    static let serviceStopTotal: TimeInterval = 90
    /// Short kubectl helper subprocesses (preflight, list).
    static let kubectlSubcommand: TimeInterval = 30
}

/// PROC-04: Avoid blocking Swift Concurrency cooperative threads on `Process.waitUntilExit()`.
enum SubprocessWait: Sendable {
    /// Waits until the process exits. Returns whether exit was observed (always `true` without a timeout).
    @discardableResult
    nonisolated static func waitForExit(of process: Process, timeout: TimeInterval? = nil) async -> Bool {
        guard let timeout, timeout > 0 else {
            await Task.detached(priority: .utility) {
                process.waitUntilExit()
            }.value
            return true
        }

        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await Task.detached(priority: .utility) {
                    process.waitUntilExit()
                }.value
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if finished { return true }

        terminateProcessIfRunning(process)
        await Task.detached(priority: .utility) {
            if process.isRunning {
                process.waitUntilExit()
            }
        }.value
        return false
    }

    /// Runs `operation` concurrently with a wall-clock limit. Returns `false` if the limit was hit first.
    nonisolated static func runWithinTimeout(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) async -> Bool {
        guard timeout > 0 else {
            await operation()
            return true
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await operation()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    nonisolated private static func terminateProcessIfRunning(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        usleep(500_000)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
