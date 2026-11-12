import SwiftUI

// MARK: - Global Alert Modifier View Extension

public struct KumaGlobalAlertModifier: ViewModifier {
    var alertService: AlertService = .shared

    public func body(content: Content) -> some View {
        content
            .alert(
                alertService.activeAlert?.title ?? "",
                isPresented: Binding(
                    get: { alertService.activeAlert != nil },
                    set: { if !$0 { alertService.dismiss() } }
                ),
                presenting: alertService.activeAlert
            ) { payload in
                if let secondary = payload.secondaryButton {
                    Button(secondary.title, role: secondary.role) {
                        secondary.action?()
                    }
                }

                Button(payload.primaryButton.title, role: payload.primaryButton.role) {
                    payload.primaryButton.action?()
                }
            } message: { payload in
                Text(payload.message)
            }
    }
}

extension View {
    public func withKumaAlerts() -> some View {
        self.modifier(KumaGlobalAlertModifier())
    }
}
