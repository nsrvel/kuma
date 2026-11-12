import Foundation

enum ServiceStartContext: Sendable {
    case userInitiated(serviceName: String?)
    case autoReconnect(attempt: Int, maxAttempts: Int)
}

/// Shared start pipeline for deck, inspector, and auto-reconnect attempts.
enum ServiceStartSupport {
    static func start(
        serviceID: UUID,
        stateStore: ServiceStateStore?,
        context: ServiceStartContext
    ) async -> Result<Void, Error> {
        await MainActor.run {
            stateStore?.setExecutionState(.starting, for: serviceID)
        }

        do {
            try await ServiceExecutionEngine.shared.start(serviceID: serviceID)
            await ServiceExecutionStateSync.applyAfterSuccessfulStart(
                serviceID: serviceID,
                stateStore: stateStore
            )
            return .success(())
        } catch {
            if case .userInitiated(let serviceName) = context {
                await MainActor.run {
                    applyUserStartFailure(
                        serviceID: serviceID,
                        stateStore: stateStore,
                        error: error,
                        serviceName: serviceName
                    )
                }
            }
            return .failure(error)
        }
    }

    @MainActor
    private static func applyUserStartFailure(
        serviceID: UUID,
        stateStore: ServiceStateStore?,
        error: Error,
        serviceName: String?
    ) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        stateStore?.setLastFailureMessage(message, for: serviceID)
        stateStore?.setExecutionState(.crashed(exitCode: 1), for: serviceID)
        ServiceStartFailurePresenter.present(error: error, serviceName: serviceName)
    }
}
