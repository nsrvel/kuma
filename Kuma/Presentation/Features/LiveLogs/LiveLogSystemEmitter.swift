import Foundation

enum LiveLogSystemEmitter: Sendable {
    private static var recording: SystemActivityLogRecordingBackend { SystemActivityLogRecording.shared }

    static func beginRun(serviceID: UUID) async {
        await recording.beginRun(serviceID: serviceID)
    }

    static func endCapture(serviceID: UUID) async {
        await recording.endCapture(serviceID: serviceID)
    }

    static func emit(serviceID: UUID, message: String) async {
        await recording.emit(serviceID: serviceID, message: message)
    }

    static func emitBatch(serviceID: UUID, messages: [String]) async {
        await recording.emitBatch(serviceID: serviceID, messages: messages)
    }

    static func emitRawLine(serviceID: UUID, message: String) async {
        await recording.emitRawLine(serviceID: serviceID, message: message)
    }

    static func recordBannerFailure(serviceID: UUID, message: String) async {
        await recording.recordFailure(serviceID: serviceID, message: message)
    }

    static func recordConfigurationIssues(serviceID: UUID, messages: [String]) async {
        await recording.recordConfigurationIssues(serviceID: serviceID, messages: messages)
    }
}
