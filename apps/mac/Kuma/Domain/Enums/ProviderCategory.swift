import Foundation

public enum ProviderCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case docker
    case kubernetes
    case podman
    case shell
    case ssh
    case httpCheck
    case tunnel
    case processMonitor

    // MARK: - Short Sidebar Display Name

    public nonisolated var sidebarLabel: String {
        switch self {
        case .docker:         return "Docker"
        case .kubernetes:     return "Kubernetes"
        case .podman:         return "Podman"
        case .shell:          return "Shell"
        case .ssh:            return "SSH"
        case .httpCheck:      return "Health Check"
        case .tunnel:         return "Tunnel"
        case .processMonitor: return "Process Monitor"
        }
    }

    // MARK: - Deterministic Stable ID

    public var stableID: UUID {
        .stable("provider.\(rawValue)")
    }

    // MARK: - Tooltip for [+] Action

    /// Managed processes that can use per-provider auto reconnect after unexpected exit.
    public nonisolated var supportsAutoReconnect: Bool {
        switch self {
        case .kubernetes, .ssh, .shell:
            return true
        case .docker, .podman, .httpCheck, .tunnel, .processMonitor:
            return false
        }
    }

    public var addTooltip: String {
        switch self {
        case .docker:         return "New Docker Service"
        case .kubernetes:     return "New Kubernetes Service"
        case .podman:         return "New Podman Service"
        case .shell:          return "New Shell Service"
        case .ssh:            return "New SSH Service"
        case .httpCheck:      return "New Health Check Service"
        case .tunnel:         return "New Tunnel Service"
        case .processMonitor: return "New Process Monitor Service"
        }
    }
}
