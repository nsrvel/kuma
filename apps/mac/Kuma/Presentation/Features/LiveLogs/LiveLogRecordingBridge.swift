import Foundation

/// Forwards system activity recording to `LiveLogSession` on the main actor.
public final class LiveLogRecordingBridge: SystemActivityLogRecordingBackend, @unchecked Sendable {
    public init() {}

    public func beginRun(serviceID: UUID) async {
        await MainActor.run { LiveLogSession.shared.beginRun(serviceID: serviceID) }
    }

    public func endCapture(serviceID: UUID) async {
        await MainActor.run { LiveLogSession.shared.endCapture(serviceID: serviceID) }
    }

    public func emit(serviceID: UUID, message: String) async {
        await MainActor.run { LiveLogSession.shared.emitSystem(serviceID: serviceID, message: message) }
    }

    public func emitBatch(serviceID: UUID, messages: [String]) async {
        await MainActor.run { LiveLogSession.shared.emitSystemBatch(serviceID: serviceID, messages: messages) }
    }

    public func emitRawLine(serviceID: UUID, message: String) async {
        await MainActor.run { LiveLogSession.shared.emitRawLine(serviceID: serviceID, message: message) }
    }

    public func recordFailure(serviceID: UUID, message: String) async {
        await MainActor.run { LiveLogSession.shared.recordBannerFailure(serviceID: serviceID, message: message) }
    }

    public func recordConfigurationIssues(serviceID: UUID, messages: [String]) async {
        await MainActor.run {
            LiveLogSession.shared.recordConfigurationIssues(serviceID: serviceID, messages: messages)
        }
    }
}
