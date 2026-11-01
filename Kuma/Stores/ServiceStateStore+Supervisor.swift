import Foundation

extension ServiceStateStore {
    /// Subscribes to coalesced execution snapshots (call once at app launch).
    public func bindExecutionSupervisor() {
        Task {
            let stream = await ExecutionSupervisor.shared.snapshotStream()
            for await snapshot in stream {
                await MainActor.run {
                    applySupervisorSnapshot(snapshot)
                }
            }
        }
    }

    private func applySupervisorSnapshot(_ snapshot: [UUID: ExecutionRecord]) {
        for (serviceID, record) in snapshot {
            let existing = executionStates[serviceID] ?? .idle
            if existing == .starting || existing == .stopping { continue }
            let next = record.executionState
            if Self.shouldIgnoreSupervisorTransitionDuringReconnect(from: existing, to: next) {
                continue
            }
            guard existing != next else { continue }
            if let failure = record.lastFailure {
                applyLastFailure(failure, for: serviceID)
            } else if record.serviceState != .crashed {
                applyLastFailure(nil, for: serviceID)
            }
            setExecutionState(next, for: serviceID)
        }
        for serviceID in executionStates.keys where snapshot[serviceID] == nil {
            let existing = executionStates[serviceID] ?? .idle
            if existing == .starting || existing == .stopping { continue }
            if existing.isReconnecting { continue }
            if existing != .idle {
                setExecutionState(.idle, for: serviceID)
            }
        }
    }

    /// Ignores stale supervisor downgrades while the UI is in auto-reconnect backoff.
    static func shouldIgnoreSupervisorTransitionDuringReconnect(
        from existing: ServiceExecutionState,
        to next: ServiceExecutionState
    ) -> Bool {
        guard existing.isReconnecting else { return false }
        switch next {
        case .idle, .starting:
            return true
        default:
            return false
        }
    }
}
