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
            stateStore?.setExecutionState(.starting, for: id)
            do {
                try await ServiceExecutionEngine.shared.start(serviceID: id)
                await ServiceExecutionStateSync.applyAfterSuccessfulStart(serviceID: id, stateStore: stateStore)
            } catch {
                Self.logger.error("Failed to start service \(id): \(error.localizedDescription)")
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stateStore?.setLastFailureMessage(message, for: id)
                stateStore?.setExecutionState(.crashed(exitCode: 1), for: id)
                ServiceStartFailurePresenter.present(
                    error: error,
                    serviceName: snapshots.first(where: { $0.id == id })?.name
                )
            }
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

                stateStore?.setExecutionState(.starting, for: snapshot.id)
                do {
                    try await ServiceExecutionEngine.shared.start(serviceID: snapshot.id)
                    await ServiceExecutionStateSync.applyAfterSuccessfulStart(
                        serviceID: snapshot.id,
                        stateStore: stateStore
                    )
                } catch {
                    Self.logger.error("Failed to start service \(snapshot.name): \(error.localizedDescription)")
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    stateStore?.setLastFailureMessage(message, for: snapshot.id)
                    stateStore?.setExecutionState(.crashed(exitCode: 1), for: snapshot.id)
                    ServiceStartFailurePresenter.present(error: error, serviceName: snapshot.name)
                }

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

            stateStore?.setExecutionState(.starting, for: id)
            do {
                try await ServiceExecutionEngine.shared.start(serviceID: id)
                await ServiceExecutionStateSync.applyAfterSuccessfulStart(serviceID: id, stateStore: stateStore)
            } catch {
                Self.logger.error("Failed to restart service \(id): \(error.localizedDescription)")
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                stateStore?.setLastFailureMessage(message, for: id)
                stateStore?.setExecutionState(.crashed(exitCode: 1), for: id)
                ServiceStartFailurePresenter.present(
                    error: error,
                    serviceName: snapshots.first(where: { $0.id == id })?.name
                )
            }

            notifyExecutionStatesChanged()
        }
    }
}
