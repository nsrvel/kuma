import Foundation

// MARK: - Service State

public enum ServiceState: String, Codable, Sendable, CaseIterable {
    case stopped
    case starting
    case running
    case stopping
    case reconnecting
    case crashed

    public var title: String {
        switch self {
        case .stopped:  return "Stopped"
        case .starting: return "Starting"
        case .running:  return "Running"
        case .stopping: return "Stopping"
        case .reconnecting: return "Reconnecting"
        case .crashed:  return "Crashed"
        }
    }

    public var isOperational: Bool {
        self == .running || self == .starting || self == .reconnecting
    }

    /// Natural status sorting priority (Running > Starting > Stopping > Crashed > Stopped)
    public var sortPriority: Int {
        switch self {
        case .running:  return 0
        case .starting: return 1
        case .reconnecting: return 2
        case .stopping: return 3
        case .crashed:  return 4
        case .stopped:  return 5
        }
    }
}
