import Foundation

/// Runs engine stop off the main actor, then clears `.stopping` on the UI store.
enum ServiceStopSupport {
    static func stopOffMainActor(serviceID: UUID, stateStore: ServiceStateStore?) async {
        let finished = await SubprocessWait.runWithinTimeout(KumaExecutionTimeouts.serviceStopTotal) {
            await ServiceExecutionEngine.shared.stop(serviceID: serviceID)
        }
        if !finished {
            await ServiceExecutionEngine.shared.forceReleaseService(serviceID: serviceID)
        }
        await ServiceExecutionStateSync.applyAfterStop(serviceID: serviceID, stateStore: stateStore)
    }
}
