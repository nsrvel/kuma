import Foundation

// MARK: - Service Status Filter Option

public enum ServiceStatusFilterOption: String, Codable, Sendable, CaseIterable, Hashable {
    case running = "running"
    case stopped = "stopped"
    case crashed = "crashed"
    case disabled = "disabled"

    public var title: String {
        switch self {
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .crashed:  return "Crashed"
        case .disabled: return "Disabled"
        }
    }
}

// MARK: - Deck View Mode

public enum DeckViewMode: String, Codable, Sendable, CaseIterable {
    case card
    case table
}

// MARK: - Service Sort Option

public enum ServiceSortOption: String, Codable, Sendable, CaseIterable {
    case name = "Name"
    case status = "Status"
    case created = "Date Created"
}
