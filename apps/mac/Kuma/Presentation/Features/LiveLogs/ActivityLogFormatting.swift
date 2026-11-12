import Foundation

public enum ActivityLogCategory: String, Equatable, Sendable {
    case kuma
    case failure
    case failureContinuation
    case config
    case health
    case monitor
    case raw

    public static func infer(from text: String) -> ActivityLogCategory {
        if text.hasPrefix("[KUMA] ") { return .kuma }
        if text.hasPrefix("[FAILURE] ") { return .failure }
        if text.hasPrefix("[CONFIG] ") { return .config }
        if text.hasPrefix("[HEALTH] ") { return .health }
        if text.hasPrefix("[MONITOR] ") { return .monitor }
        if text.hasPrefix("  ") { return .failureContinuation }
        return .raw
    }
}

public enum ActivityLogFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func displayMessage(from text: String, category: ActivityLogCategory) -> String {
        switch category {
        case .kuma:
            return stripPrefix("[KUMA] ", from: text)
        case .failure:
            return stripPrefix("[FAILURE] ", from: text)
        case .failureContinuation:
            return text.trimmingCharacters(in: .whitespaces)
        case .config:
            return stripPrefix("[CONFIG] ", from: text)
        case .health:
            return stripPrefix("[HEALTH] ", from: text)
        case .monitor:
            return stripPrefix("[MONITOR] ", from: text)
        case .raw:
            return text
        }
    }

    private static func stripPrefix(_ prefix: String, from text: String) -> String {
        text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    }
}
