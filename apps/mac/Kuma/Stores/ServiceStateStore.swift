import Foundation
import Observation
import os

/// Central reactive bridge and single source of truth for service execution states across Kuma.
/// Shared by both ServicesDeckView and ServiceInspectorView to guarantee 100% synchronized state
/// without redundant database roundtrips or optimistic divergence.
@MainActor
@Observable
public final class ServiceStateStore {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "ServiceStateStore")

    /// Single source of truth for service execution states
    public private(set) var executionStates: [UUID: ServiceExecutionState] = [:]

    /// Last crash / failure detail from the execution supervisor (inspector banner).
    public private(set) var lastFailureMessages: [UUID: String] = [:]

    private let processRegistry: ProcessRegistry

    public init(processRegistry: ProcessRegistry = .shared) {
        self.processRegistry = processRegistry
    }

    /// Fast O(1) state lookup with graceful fallback to .idle
    public func state(for serviceID: UUID) -> ServiceExecutionState {
        executionStates[serviceID] ?? .idle
    }

    /// If stop was requested but the UI task never reached `.idle`, unwind a stuck `.stopping` pill.
    public func clearStoppingIfStillPending(for serviceID: UUID) {
        guard state(for: serviceID) == .stopping else { return }
        setExecutionState(.idle, for: serviceID)
    }

    /// Fast O(1) runtime wrapper for backwards compatibility with subviews
    public func runtime(for serviceID: UUID) -> ServiceRuntimeState {
        ServiceRuntimeState(executionState: state(for: serviceID))
    }

    /// True when any service is starting/stopping (deck still needs runtime notifications).
    public var hasTransientExecutionStates: Bool {
        executionStates.values.contains { $0 == .starting || $0 == .stopping || $0.isReconnecting }
    }

    /// IDs of services currently in an operational state (running or starting)
    public var activeServiceIDs: [UUID] {
        executionStates.compactMap { id, state in
            state.isOperational ? id : nil
        }
    }

    public func setExecutionState(_ state: ServiceExecutionState, for serviceID: UUID) {
        guard executionStates[serviceID] != state else { return }
        executionStates[serviceID] = state
        if case .idle = state {
            lastFailureMessages.removeValue(forKey: serviceID)
        }
    }

    public func lastFailure(for serviceID: UUID) -> String? {
        lastFailureMessages[serviceID]
    }

    public func setLastFailureMessage(_ message: String?, for serviceID: UUID) {
        applyLastFailure(message, for: serviceID)
    }

    func applyLastFailure(_ message: String?, for serviceID: UUID) {
        if let message {
            lastFailureMessages[serviceID] = message
            Task { await SystemActivityLogRecording.shared.recordFailure(serviceID: serviceID, message: message) }
        } else {
            lastFailureMessages.removeValue(forKey: serviceID)
        }
    }

    /// Batch refreshes process states for an array of services via a single actor crossing
    public func refreshProcessStates(for serviceIDs: [UUID]) async {
        guard !serviceIDs.isEmpty else { return }
        let currentProcessStates = await ExecutionSupervisor.shared.states(for: serviceIDs)
        let idleProcessIDs = Set(currentProcessStates.compactMap { id, state in state == .idle ? id : nil })
        let runningWithoutProcess = await ExecutionSupervisor.shared.runningServiceIDs(among: idleProcessIDs)

        for (id, state) in currentProcessStates {
            let existing = executionStates[id] ?? .idle
            // Don't overwrite an in-flight .starting or .stopping transition with background snapshot
            if existing == .starting && state == .idle {
                continue
            }
            if existing.isReconnecting && (state == .idle || state == .starting) {
                continue
            }
            if existing == .stopping {
                // User requested stop — never promote back to running while compose teardown is in flight.
                if state == .idle && !runningWithoutProcess.contains(id) {
                    setExecutionState(.idle, for: id)
                }
                continue
            }
            if state == .idle {
                if runningWithoutProcess.contains(id) {
                    if !existing.isOperational {
                        setExecutionState(.running(pid: 0), for: id)
                    }
                    continue
                }
            }
            setExecutionState(state, for: id)
        }
    }

    /// Cleans up state when a service is deleted
    public func removeService(_ serviceID: UUID) {
        executionStates.removeValue(forKey: serviceID)
        lastFailureMessages.removeValue(forKey: serviceID)
    }

    /// Resets all execution states (e.g. on workspace switch)
    public func removeAll() {
        executionStates.removeAll()
        lastFailureMessages.removeAll()
    }
}
