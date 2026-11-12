import SwiftUI
import AppKit

public struct SettingsGeneralSection: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showPermissionAlert = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        KumaFormSection(
            icon: "gearshape.fill",
            title: "General"
        ) {
            VStack(alignment: .leading, spacing: KumaSpacing.lg) {
                KumaToggleField(
                    label: "Launch at Login",
                    value: $viewModel.launchAtLogin,
                    description: "Open Kuma automatically at login."
                )

                Divider().opacity(0.3)

                KumaToggleField(
                    label: "Auto-start Services",
                    value: $viewModel.autoResumeServices,
                    description: "Resume active services when Kuma launches."
                )

                Divider().opacity(0.3)

                KumaToggleField(
                    label: "Notify on Service Failure",
                    value: $viewModel.notifyOnServiceFailure,
                    description: "Notify when a service fails or exits unexpectedly."
                )
                .onChange(of: viewModel.notifyOnServiceFailure) { _, newValue in
                    handleNotifyOnServiceFailureToggle(newValue: newValue)
                }

                Divider().opacity(0.3)

                KumaToggleField(
                    label: "Confirm Before Quitting",
                    value: $viewModel.confirmBeforeQuit,
                    description: "Prompt before quitting when services are active."
                )

                if viewModel.confirmBeforeQuit && UserDefaults.standard.string(forKey: KumaSettingsKey.quitBehavior) != nil {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saved Quit Preference")
                                .font(KumaFont.subheadline)
                            Text("Clear saved preference and prompt on quit.")
                                .font(KumaFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            UserDefaults.standard.removeObject(forKey: KumaSettingsKey.quitBehavior)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .alert("Notification Permission Required", isPresented: $showPermissionAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kuma needs permission to send notifications. Please allow it in macOS System Settings.")
        }
    }

    private func handleNotifyOnServiceFailureToggle(newValue: Bool) {
        guard newValue else { return }

        Task {
            let shouldPrompt = await viewModel.requestNotificationAuthorization()
            if shouldPrompt {
                showPermissionAlert = true
            }
        }
    }
}
