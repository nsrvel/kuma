import Foundation

/// Applies `ServiceStateStore` from engine truth after start/stop (not from PID alone).
enum ServiceExecutionStateSync {
    @MainActor
    static func applyAfterSuccessfulStart(serviceID: UUID, stateStore: ServiceStateStore?) async {
        guard let stateStore else { return }
        var running = await ServiceExecutionEngine.shared.isServiceRunning(serviceID: serviceID)
        if !running {
            // Managed processes (kubectl port-forward, shell) can exit briefly before the registry updates.
            for _ in 0..<6 where !running {
                try? await Task.sleep(nanoseconds: 50_000_000)
                running = await ServiceExecutionEngine.shared.isServiceRunning(serviceID: serviceID)
            }
        }
        guard running else {
            stateStore.setExecutionState(.crashed(exitCode: 1), for: serviceID)
            return
        }
        if let proc = await ProcessRegistry.shared.getSnapshot(serviceID: serviceID) {
            stateStore.setExecutionState(.running(pid: proc.pid), for: serviceID)
        } else {
            stateStore.setExecutionState(.running(pid: 0), for: serviceID)
        }
    }

    static func applyAfterStop(serviceID: UUID, stateStore: ServiceStateStore?) async {
        await MainActor.run {
            guard let stateStore else { return }
            stateStore.setExecutionState(.idle, for: serviceID)
            stateStore.clearStoppingIfStillPending(for: serviceID)
        }
    }
}
