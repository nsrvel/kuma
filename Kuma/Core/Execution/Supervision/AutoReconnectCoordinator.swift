import Foundation
import os

/// Schedules auto-reconnect retries using the same start pipeline as manual Start.
actor AutoReconnectCoordinator {
    static let shared = AutoReconnectCoordinator()

    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "AutoReconnect")

    private struct Session {
        var attemptsCompleted: Int = 0
        var lastExitCode: Int32 = 1
        var task: Task<Void, Never>?
    }

    private var sessions: [UUID: Session] = [:]

    private final class StateStoreBox: @unchecked Sendable {
        nonisolated(unsafe) weak var store: ServiceStateStore?
    }

    private let stateStoreBox = StateStoreBox()

    private init() {}

    @MainActor
    func configure(stateStore: ServiceStateStore) {
        stateStoreBox.store = stateStore
    }

    func resetSession(serviceID: UUID) {
        sessions[serviceID]?.task?.cancel()
        sessions[serviceID] = Session(attemptsCompleted: 0, lastExitCode: 1, task: nil)
    }

    func cancel(serviceID: UUID) {
        sessions[serviceID]?.task?.cancel()
        sessions.removeValue(forKey: serviceID)
    }

    func resetForTests() {
        for id in Array(sessions.keys) {
            cancel(serviceID: id)
        }
    }

    /// Returns true when reconnect handling took over exit processing.
    func handleUnexpectedExit(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32
    ) async -> Bool {
        guard let provider = await ServiceExecutionEngine.shared.activeProvider(for: serviceID) else {
            return false
        }
        guard provider.isAutoReconnectEnabled else { return false }

        var session = sessions[serviceID] ?? Session()
        session.lastExitCode = exitCode
        session.task?.cancel()

        session.task = Task {
            await self.runReconnectLoop(
                serviceID: serviceID,
                serviceName: serviceName,
                exitCode: exitCode
            )
        }
        sessions[serviceID] = session
        return true
    }

    private func runReconnectLoop(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32
    ) async {
        let stateStore = await MainActor.run { stateStoreBox.store }

        while !Task.isCancelled {
            var session = sessions[serviceID] ?? Session(lastExitCode: exitCode)
            session.attemptsCompleted += 1
            let attempt = session.attemptsCompleted
            sessions[serviceID] = session

            if attempt > AutoReconnectPolicy.maxAttempts {
                await finishExhausted(
                    serviceID: serviceID,
                    serviceName: serviceName,
                    exitCode: session.lastExitCode
                )
                return
            }

            await ExecutionSupervisor.shared.setManagedProcessReconnecting(
                serviceID: serviceID,
                serviceName: serviceName,
                attempt: attempt,
                maxAttempts: AutoReconnectPolicy.maxAttempts
            )

            let delay = AutoReconnectPolicy.backoffNanoseconds(attempt: attempt)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            let result = await ServiceStartSupport.start(
                serviceID: serviceID,
                stateStore: stateStore,
                context: .autoReconnect(attempt: attempt, maxAttempts: AutoReconnectPolicy.maxAttempts)
            )

            switch result {
            case .success:
                resetSession(serviceID: serviceID)
                return
            case .failure(let error):
                Self.logger.warning(
                    "Auto reconnect attempt \(attempt, privacy: .public) failed for \(serviceName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                await LiveLogSystemEmitter.emit(
                    serviceID: serviceID,
                    message: "Reconnect attempt \(attempt) failed: \(error.localizedDescription)"
                )
                session = sessions[serviceID] ?? session
                session.lastExitCode = 1
                sessions[serviceID] = session
            }
        }
    }

    private func finishExhausted(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32
    ) async {
        sessions[serviceID]?.task?.cancel()
        sessions.removeValue(forKey: serviceID)
        await ExecutionSupervisor.shared.finishAutoReconnectExhausted(
            serviceID: serviceID,
            serviceName: serviceName,
            exitCode: exitCode
        )
    }
}
