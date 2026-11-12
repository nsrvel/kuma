import SwiftUI
import Observation

@MainActor
public struct KumaAlertButton: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let role: ButtonRole?
    public let action: (@MainActor @Sendable () -> Void)?

    public init(
        title: String,
        role: ButtonRole? = nil,
        action: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.title = title
        self.role = role
        self.action = action
    }

    public static func cancel(title: String = "Cancel", action: (@MainActor @Sendable () -> Void)? = nil) -> KumaAlertButton {
        KumaAlertButton(title: title, role: .cancel, action: action)
    }

    public static func destructive(title: String, action: @escaping (@MainActor @Sendable () -> Void)) -> KumaAlertButton {
        KumaAlertButton(title: title, role: .destructive, action: action)
    }

    public static func primary(title: String, action: (@MainActor @Sendable () -> Void)? = nil) -> KumaAlertButton {
        KumaAlertButton(title: title, role: nil, action: action)
    }
}

@MainActor
public struct KumaAlertPayload: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let primaryButton: KumaAlertButton
    public let secondaryButton: KumaAlertButton?

    public init(
        title: String,
        message: String,
        primaryButton: KumaAlertButton,
        secondaryButton: KumaAlertButton? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }
}

@MainActor
@Observable
public final class AlertService {
    public static let shared = AlertService()

    public var activeAlert: KumaAlertPayload? = nil

    public init() {}

    // MARK: - Presentation API

    public func show(
        title: String,
        message: String,
        primaryButton: KumaAlertButton,
        secondaryButton: KumaAlertButton? = nil
    ) {
        self.activeAlert = KumaAlertPayload(
            title: title,
            message: message,
            primaryButton: primaryButton,
            secondaryButton: secondaryButton ?? .cancel()
        )
    }

    public func showError(
        title: String = "Error",
        message: String,
        okAction: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.activeAlert = KumaAlertPayload(
            title: title,
            message: message,
            primaryButton: .primary(title: "OK", action: okAction),
            secondaryButton: nil
        )
    }

    public func confirmDelete(
        title: String,
        message: String,
        confirmTitle: String = "Delete",
        onConfirm: @escaping (@MainActor @Sendable () -> Void)
    ) {
        self.activeAlert = KumaAlertPayload(
            title: title,
            message: message,
            primaryButton: .destructive(title: confirmTitle, action: onConfirm),
            secondaryButton: .cancel()
        )
    }

    public func dismiss() {
        self.activeAlert = nil
    }
}

