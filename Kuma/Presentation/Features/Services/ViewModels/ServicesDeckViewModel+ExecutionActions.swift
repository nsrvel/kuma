import Foundation
import os

extension ServicesDeckViewModel {
    public func toggleService(id: UUID) {
        if isOperational(id) {
            stateStore?.setExecutionState(.stopping, for: id)
            let store = stateStore
            Task.detached(priority: .userInitiated) {
                await ServiceStopSupport.stopOffMainActor(serviceID: id, stateStore: store)
            }
            return
        }
        Task {
            await toggleServiceAsync(id: id)
        }
    }

    public func toggleServiceAsync(id: UUID) async {
        let wasRunning = isOperational(id)

        if wasRunning {
            stateStore?.setExecutionState(.stopping, for: id)
            await ServiceStopSupport.stopOffMainActor(serviceID: id, stateStore: stateStore)
        } else {
            let serviceName = snapshots.first(where: { $0.id == id })?.name
            _ = await ServiceStartSupport.start(
                serviceID: id,
                stateStore: stateStore,
                context: .userInitiated(serviceName: serviceName)
            )
        }

        notifyExecutionStatesChanged()
    }

    public func startAllServices() {
        Task {
            let targetSnapshots = bulkActionSnapshots.filter { snapshot in
                !snapshot.isDisabled && !isOperational(snapshot.id)
            }

            for snapshot in targetSnapshots {
                guard !isOperational(snapshot.id) else { continue }

                _ = await ServiceStartSupport.start(
                    serviceID: snapshot.id,
                    stateStore: stateStore,
                    context: .userInitiated(serviceName: snapshot.name)
                )

                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            notifyExecutionStatesChanged()
        }
    }

    public func stopAllServices() {
        Task {
            let runningIDs = bulkActionSnapshots.map(\.id).filter { isOperational($0) }

            for id in runningIDs {
                stateStore?.setExecutionState(.stopping, for: id)
                await ServiceStopSupport.stopOffMainActor(serviceID: id, stateStore: stateStore)
            }

            notifyExecutionStatesChanged()
        }
    }

    public func restartService(id: UUID) {
        Task {
            stateStore?.setExecutionState(.stopping, for: id)
            await ServiceStopSupport.stopOffMainActor(serviceID: id, stateStore: stateStore)
            try? await Task.sleep(nanoseconds: 300_000_000)

            let serviceName = snapshots.first(where: { $0.id == id })?.name
            _ = await ServiceStartSupport.start(
                serviceID: id,
                stateStore: stateStore,
                context: .userInitiated(serviceName: serviceName)
            )

            notifyExecutionStatesChanged()
        }
    }
}
