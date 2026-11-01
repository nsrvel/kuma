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
            _ = await ServiceStartSupport.start(
                serviceID: serviceID,
                stateStore: stateStore,
                context: .userInitiated(serviceName: service?.name)
            )
            postUpdatedNotification()
        }
    }
}
