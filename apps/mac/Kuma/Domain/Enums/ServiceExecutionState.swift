import Foundation

/// Discrete enum representing the execution state of a service process.
/// Eliminates multi-boolean state flags (isRunning, isLoading, isStarting, etc.)
/// adhering strictly to AGENTS.md rules.
public enum ServiceExecutionState: Sendable, Equatable {
    case idle
    case starting
    case running(pid: Int32)
    case stopping
    case reconnecting(attempt: Int, maxAttempts: Int)
    case crashed(exitCode: Int32)
    case failed(reason: String)

    /// Whether the service is actively running or in the process of starting up.
    public var isOperational: Bool {
        switch self {
        case .running, .starting, .reconnecting:
            return true
        case .idle, .stopping, .crashed, .failed:
            return false
        }
    }

    /// Whether the service is currently transitioning between operational states.
    public var isLoading: Bool {
        switch self {
        case .starting, .stopping, .reconnecting:
            return true
        case .idle, .running, .crashed, .failed:
            return false
        }
    }

    /// Associated process ID if running, nil otherwise.
    public var processIdentifier: Int32? {
        if case .running(let pid) = self {
            return pid
        }
        return nil
    }

    /// Display title for user-facing status pills and badges.
    public var title: String {
        switch self {
        case .idle:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case .stopping:
            return "Stopping"
        case .reconnecting(let attempt, let maxAttempts):
            return "Reconnecting (\(attempt)/\(maxAttempts))"
        case .crashed:
            return "Crashed"
        case .failed:
            return "Failed"
        }
    }

    /// Equivalent ServiceState for backward-compatibility with filters and legacy records.
    public var legacyState: ServiceState {
        switch self {
        case .idle:
            return .stopped
        case .starting:
            return .starting
        case .running:
            return .running
        case .stopping:
            return .stopping
        case .reconnecting:
            return .reconnecting
        case .crashed, .failed:
            return .crashed
        }
    }

    /// Natural status sorting priority (Running > Starting > Stopping > Crashed > Failed > Idle)
    public var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }

    public var sortPriority: Int {
        switch self {
        case .running:  return 0
        case .starting: return 1
        case .reconnecting: return 2
        case .stopping: return 3
        case .crashed:  return 4
        case .failed:   return 5
        case .idle:     return 6
        }
    }
}
