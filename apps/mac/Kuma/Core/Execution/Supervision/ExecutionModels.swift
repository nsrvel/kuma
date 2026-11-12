import Foundation

public enum ExecutionMode: String, Sendable {
    case managedProcess
    case composeStack
    case poller
}

public struct ExecutionRecord: Sendable, Equatable {
    public let serviceID: UUID
    public let serviceName: String
    public let mode: ExecutionMode
    public let serviceState: ServiceState
    public let pid: Int32?
    public let exitCode: Int32?
    public let startedAt: Date?
    public let lastFailure: String?
    public let reconnectAttempt: Int?
    public let reconnectMax: Int?

    public nonisolated init(
        serviceID: UUID,
        serviceName: String,
        mode: ExecutionMode,
        serviceState: ServiceState,
        pid: Int32? = nil,
        exitCode: Int32? = nil,
        startedAt: Date? = nil,
        lastFailure: String? = nil,
        reconnectAttempt: Int? = nil,
        reconnectMax: Int? = nil
    ) {
        self.serviceID = serviceID
        self.serviceName = serviceName
        self.mode = mode
        self.serviceState = serviceState
        self.pid = pid
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.lastFailure = lastFailure
        self.reconnectAttempt = reconnectAttempt
        self.reconnectMax = reconnectMax
    }

    public nonisolated var executionState: ServiceExecutionState {
        switch serviceState {
        case .stopped: return .idle
        case .starting: return .starting
        case .running: return .running(pid: pid ?? 0)
        case .stopping: return .stopping
        case .reconnecting:
            let attempt = reconnectAttempt ?? 1
            let max = reconnectMax ?? AutoReconnectPolicy.maxAttempts
            return .reconnecting(attempt: attempt, maxAttempts: max)
        case .crashed: return .crashed(exitCode: exitCode ?? 1)
        }
    }
}

public enum ExecutionHandle: Sendable {
    case managedProcess(serviceID: UUID, serviceName: String, pid: pid_t, startedAt: Date)
    case composeStack(serviceID: UUID, serviceName: String, context: ComposeStackContext)
    case pollerHealth(serviceID: UUID, serviceName: String, url: URL, intervalSeconds: Int)
    case pollerProcess(serviceID: UUID, serviceName: String, processName: String, intervalSeconds: Int)
}
