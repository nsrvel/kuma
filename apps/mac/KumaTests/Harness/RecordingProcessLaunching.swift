import Foundation
import os
@testable import Kuma

/// Records the last process launch for runner integration tests (TC-D05 / TC-D06).
public final class RecordingProcessLaunching: ProcessLaunching, @unchecked Sendable {
    public struct LaunchRecord: Sendable, Equatable {
        public let executable: String
        public let arguments: [String]
        public let workingDirectory: String?
    }

    private struct State {
        var lastLaunch: LaunchRecord?
        var runningIDs: Set<UUID> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public nonisolated init() {}

    public nonisolated var lastLaunch: LaunchRecord? {
        state.withLock { $0.lastLaunch }
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
        state.withLock {
            $0.lastLaunch = LaunchRecord(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
            $0.runningIDs.insert(serviceID)
        }
        return 42_424
    }

    public nonisolated func stop(serviceID: UUID) async {
        state.withLock { $0.runningIDs.remove(serviceID) }
    }

    public nonisolated func isRunning(serviceID: UUID) async -> Bool {
        state.withLock { $0.runningIDs.contains(serviceID) }
    }

    public nonisolated func adoptExternalProcess(serviceID: UUID, serviceName: String, pid: pid_t) async {
        state.withLock { $0.runningIDs.insert(serviceID) }
    }
}
