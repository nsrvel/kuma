import Foundation

/// Coalesces overlapping stop requests for the same service (e.g. deck + inspector).
actor ServiceStopGate {
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    func runOnce(serviceID: UUID, operation: @Sendable @escaping () async -> Void) async {
        if let existing = inFlight[serviceID] {
            await existing.value
            return
        }
        let task = Task {
            await operation()
        }
        inFlight[serviceID] = task
        await task.value
        inFlight.removeValue(forKey: serviceID)
    }
}
