import Foundation
import os

extension ServiceInspectorViewModel {
    public func toggleRunning() {
        if isRunning {
            stateStore?.setExecutionState(.stopping, for: serviceID)
            let sid = serviceID
            let store = stateStore
            Task.detached(priority: .userInitiated) {
                await ServiceStopSupport.stopOffMainActor(serviceID: sid, stateStore: store)
                await MainActor.run {
                    KumaServiceNotification.postServiceUpdated(
                        serviceID: sid,
                        source: KumaServiceNotification.sourceInspector
                    )
                }
            }
            return
        }
        guard canStartService else { return }
        Task {
            guard await validateConfigurationForStart() else {
                await logBlockingConfigurationIssuesToActivity()
                return
            }
            configurationIssues = []
            stateStore?.setExecutionState(.starting, for: serviceID)
            do {
                try await ServiceExecutionEngine.shared.start(serviceID: serviceID)
                await ServiceExecutionStateSync.applyAfterSuccessfulStart(
                    serviceID: serviceID,
                    stateStore: stateStore
                )
            } catch {
                Self.logger.error("Failed to start service \(self.serviceID): \(error.localizedDescription)")
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stateStore?.setLastFailureMessage(message, for: serviceID)
                stateStore?.setExecutionState(.crashed(exitCode: 1), for: serviceID)
                ServiceStartFailurePresenter.present(error: error, serviceName: service?.name)
            }
            postUpdatedNotification()
        }
    }
}
