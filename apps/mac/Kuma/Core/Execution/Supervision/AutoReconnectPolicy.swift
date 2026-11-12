import Foundation

enum AutoReconnectPolicy: Sendable {
    nonisolated static let maxAttempts = 3

    /// Backoff before each reconnect attempt (attempt is 1-based).
    nonisolated static func backoffNanoseconds(attempt: Int) -> UInt64 {
        let seconds: UInt64
        switch attempt {
        case 1: seconds = 2
        case 2: seconds = 5
        default: seconds = 10
        }
        return seconds * 1_000_000_000
    }
}
