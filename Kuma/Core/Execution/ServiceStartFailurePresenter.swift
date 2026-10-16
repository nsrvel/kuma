import Foundation

@MainActor
public enum ServiceStartFailurePresenter {
    public static func present(
        error: Error,
        serviceName: String?,
        userDefaults: UserDefaults = .standard
    ) {
        if case ServiceExecutionError.portInUse = error {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            AlertService.shared.showError(
                title: PortConflictMessaging.alertTitle,
                message: message
            )
            return
        }

        guard PortConflictMessaging.currentPortConflictPolicy(userDefaults: userDefaults) == .warnAndBlock else { return }
        guard case ServiceExecutionError.processFailed(let reason) = error else { return }
        guard PortConflictMessaging.isComposePortConflictMessage(reason) else { return }

        AlertService.shared.showError(
            title: PortConflictMessaging.alertTitle,
            message: reason
        )
    }
}
