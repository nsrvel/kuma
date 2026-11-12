import Foundation

public struct ConfigurationIssue: Identifiable, Equatable, Sendable {
    public enum Severity: Sendable {
        case blocking
        case warning
    }

    public let code: String
    public let message: String
    public let severity: Severity

    public var id: String { code }

    public init(code: String, message: String, severity: Severity = .blocking) {
        self.code = code
        self.message = message
        self.severity = severity
    }
}
