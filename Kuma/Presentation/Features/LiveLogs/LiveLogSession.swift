import Foundation
import Observation

/// In-memory system activity log per service (no disk persistence).
@MainActor
@Observable
public final class LiveLogSession {
    public static let shared = LiveLogSession()

    private var buffers: [UUID: [LiveLogLine]] = [:]
    private var revisions: [UUID: UInt64] = [:]
    private var lastTouchedAt: [UUID: Date] = [:]
    /// Services with an active run capture (`beginRun` until `endCapture`, `clear`, or next `beginRun`).
    private var capturingServiceIDs: Set<UUID> = []
    private var trimNoticeServiceIDs: Set<UUID> = []
    private var lastRecordedFailureText: [UUID: String] = [:]

    private let maxLines = 1_000
    // ponytail: LRU cap; raise or persist-to-disk if users routinely exceed 50 services
    private var maxRetainedServices = 50

    private init() {}

    public enum LiveLogLineKind: String, Equatable, Sendable {
        case system
        case workload
    }

    public struct LiveLogLine: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let text: String
        public let timestamp: Date
        public let kind: LiveLogLineKind
        public let category: ActivityLogCategory

        public init(
            id: UUID = UUID(),
            text: String,
            timestamp: Date = Date(),
            kind: LiveLogLineKind = .system,
            category: ActivityLogCategory = .raw
        ) {
            self.id = id
            self.text = text
            self.timestamp = timestamp
            self.kind = kind
            self.category = category
        }
    }

    public struct ServiceSnapshot: Equatable, Sendable {
        public let revision: UInt64
        public let lines: [LiveLogLine]
    }

    public func snapshot(for serviceID: UUID) -> ServiceSnapshot {
        ServiceSnapshot(revision: revisions[serviceID] ?? 0, lines: buffers[serviceID] ?? [])
    }

    public func lines(for serviceID: UUID) -> [LiveLogLine] {
        buffers[serviceID] ?? []
    }

    /// LRU recency for buffer retention — call from inspector `onAppear`, not from SwiftUI `body`.
    public func markRecentlyUsed(serviceID: UUID) {
        touch(serviceID: serviceID)
    }

    public func revision(for serviceID: UUID) -> UInt64 {
        revisions[serviceID] ?? 0
    }

    public func didTrimToMaxLines(for serviceID: UUID) -> Bool {
        trimNoticeServiceIDs.contains(serviceID)
    }

    /// Starts a new run: clears prior system log for this service and enables capture.
    public func beginRun(serviceID: UUID) {
        capturingServiceIDs.insert(serviceID)
        trimNoticeServiceIDs.remove(serviceID)
        lastRecordedFailureText.removeValue(forKey: serviceID)
        ensureBufferSlot(for: serviceID)
        buffers[serviceID] = []
        bumpRevision(serviceID: serviceID)
        touch(serviceID: serviceID)
    }

    /// Stops appending new lines; existing buffer is kept for the inspector.
    public func endCapture(serviceID: UUID) {
        capturingServiceIDs.remove(serviceID)
    }

    public func clear(serviceID: UUID) {
        buffers.removeValue(forKey: serviceID)
        revisions.removeValue(forKey: serviceID)
        lastTouchedAt.removeValue(forKey: serviceID)
        capturingServiceIDs.remove(serviceID)
        trimNoticeServiceIDs.remove(serviceID)
        lastRecordedFailureText.removeValue(forKey: serviceID)
    }

    public func clearAll() {
        buffers.removeAll()
        revisions.removeAll()
        lastTouchedAt.removeAll()
        capturingServiceIDs.removeAll()
        trimNoticeServiceIDs.removeAll()
        lastRecordedFailureText.removeAll()
    }

    public func acknowledgeTrimNotice(for serviceID: UUID) {
        trimNoticeServiceIDs.remove(serviceID)
    }

    public func emitSystem(serviceID: UUID, message: String) {
        guard capturingServiceIDs.contains(serviceID) else { return }
        appendSystemLine(serviceID: serviceID, text: "[KUMA] \(message)")
    }

    public func emitSystemBatch(serviceID: UUID, messages: [String]) {
        guard capturingServiceIDs.contains(serviceID) else { return }
        for message in messages {
            appendSystemLine(serviceID: serviceID, text: "[KUMA] \(message)")
        }
    }

    public func emitRawLine(serviceID: UUID, message: String) {
        guard capturingServiceIDs.contains(serviceID) else { return }
        appendSystemLine(serviceID: serviceID, text: message)
    }

    /// Enables capture without clearing (config / banner sync before a run).
    public func ensureCapturing(serviceID: UUID) {
        capturingServiceIDs.insert(serviceID)
        ensureBufferSlot(for: serviceID)
        if buffers[serviceID] == nil {
            buffers[serviceID] = []
            bumpRevision(serviceID: serviceID)
        }
        touch(serviceID: serviceID)
    }

    /// Full failure text shown (truncated) on the inspector banner.
    public func recordBannerFailure(serviceID: UUID, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ensureCapturing(serviceID: serviceID)
        if lastRecordedFailureText[serviceID] == trimmed { return }
        let startFailedLine = "[KUMA] Start failed: \(trimmed)"
        if buffers[serviceID]?.contains(where: { $0.text == startFailedLine }) == true {
            lastRecordedFailureText[serviceID] = trimmed
            return
        }
        let parts = trimmed.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return }
        lastRecordedFailureText[serviceID] = trimmed
        appendSystemLine(serviceID: serviceID, text: "[FAILURE] \(first)", category: .failure)
        for line in parts.dropFirst() {
            appendSystemLine(serviceID: serviceID, text: "  \(line)", category: .failureContinuation)
        }
    }

    /// Blocking configuration messages (banner shows first + count).
    public func recordConfigurationIssues(serviceID: UUID, messages: [String]) {
        let trimmed = messages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return }
        ensureCapturing(serviceID: serviceID)
        let existing = Set((buffers[serviceID] ?? []).map(\.text))
        for message in trimmed {
            let line = "[CONFIG] \(message)"
            guard !existing.contains(line) else { continue }
            appendSystemLine(serviceID: serviceID, text: line, category: .config)
        }
    }

    /// Align log with banner when opening the panel (failure + config hints).
    public func syncBannerContext(
        serviceID: UUID,
        lastFailure: String?,
        configurationMessages: [String]
    ) {
        if let lastFailure {
            recordBannerFailure(serviceID: serviceID, message: lastFailure)
        }
        recordConfigurationIssues(serviceID: serviceID, messages: configurationMessages)
    }

    internal func testing_beginRun(_ serviceID: UUID) {
        beginRun(serviceID: serviceID)
    }

    internal func testing_setMaxRetainedServices(_ value: Int) {
        maxRetainedServices = max(1, value)
    }

    private func ensureBufferSlot(for serviceID: UUID) {
        if buffers[serviceID] != nil {
            touch(serviceID: serviceID)
            return
        }
        while buffers.count >= maxRetainedServices {
            guard let victim = lastTouchedAt.min(by: { $0.value < $1.value })?.key else { break }
            clear(serviceID: victim)
        }
        touch(serviceID: serviceID)
    }

    private func touch(serviceID: UUID) {
        lastTouchedAt[serviceID] = Date()
    }

    private func bumpRevision(serviceID: UUID) {
        revisions[serviceID, default: 0] += 1
    }

    private func appendSystemLine(
        serviceID: UUID,
        text: String,
        category: ActivityLogCategory? = nil
    ) {
        ensureBufferSlot(for: serviceID)
        let sanitized = ANSISanitizer.sanitize(text)
        for line in sanitized.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            guard !s.isEmpty else { continue }
            let resolved = category ?? ActivityLogCategory.infer(from: s)
            appendLine(
                serviceID: serviceID,
                line: LiveLogLine(text: s, kind: .system, category: resolved)
            )
        }
    }

    private func appendLine(serviceID: UUID, line: LiveLogLine) {
        var bucket = buffers[serviceID] ?? []
        bucket.append(line)
        if bucket.count > maxLines {
            bucket = Array(bucket.suffix(maxLines))
            trimNoticeServiceIDs.insert(serviceID)
        }
        buffers[serviceID] = bucket
        bumpRevision(serviceID: serviceID)
        touch(serviceID: serviceID)
    }
}
