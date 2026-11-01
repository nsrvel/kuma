import Foundation

/// Core-facing API for in-app system activity logs (UI implementation installed at launch).
public protocol SystemActivityLogRecordingBackend: Sendable {
    func beginRun(serviceID: UUID) async
    func endCapture(serviceID: UUID) async
    func emit(serviceID: UUID, message: String) async
    func emitBatch(serviceID: UUID, messages: [String]) async
    func emitRawLine(serviceID: UUID, message: String) async
    func recordFailure(serviceID: UUID, message: String) async
    func recordConfigurationIssues(serviceID: UUID, messages: [String]) async
}

public enum SystemActivityLogRecording {
    private final class NoOpBackend: SystemActivityLogRecordingBackend, @unchecked Sendable {
        func beginRun(serviceID: UUID) async {}
        func endCapture(serviceID: UUID) async {}
        func emit(serviceID: UUID, message: String) async {}
        func emitBatch(serviceID: UUID, messages: [String]) async {}
        func emitRawLine(serviceID: UUID, message: String) async {}
        func recordFailure(serviceID: UUID, message: String) async {}
        func recordConfigurationIssues(serviceID: UUID, messages: [String]) async {}
    }

    // ponytail: static install; upgrade path is DI via app composition root
    private nonisolated(unsafe) static var backend: SystemActivityLogRecordingBackend = NoOpBackend()

    public nonisolated static func install(_ backend: SystemActivityLogRecordingBackend) {
        self.backend = backend
    }

    public static var shared: SystemActivityLogRecordingBackend { backend }
}
