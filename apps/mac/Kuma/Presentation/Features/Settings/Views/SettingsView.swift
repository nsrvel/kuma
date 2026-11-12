import SwiftUI

public struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var workspaceStore: WorkspaceStore

    public init(viewModel: SettingsViewModel, workspaceStore: WorkspaceStore) {
        self.viewModel = viewModel
        self.workspaceStore = workspaceStore
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: KumaSpacing.xxl) {
                // User & App Preferences
                SettingsGeneralSection(viewModel: viewModel)
                SettingsAppearanceSection(viewModel: viewModel)

                // Developer & Engine Tools
                SettingsCLIToolsSection(viewModel: viewModel)
                SettingsTunnelingToolsSection(viewModel: viewModel)
                SettingsPortsConnectionsSection(viewModel: viewModel)

                // Data
                SettingsDataSection(viewModel: viewModel, workspaceStore: workspaceStore)

                // App Version & Metadata Footer
                VStack(spacing: KumaSpacing.xs) {
                    Text("Kuma v\(appVersion) (\(buildNumber))")
                        .font(KumaFont.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, KumaSpacing.sm)
                .padding(.bottom, KumaSpacing.lg)
            }
            .padding(.horizontal, KumaSpacing.xxl)
            .padding(.vertical, KumaSpacing.xl)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    SettingsView(
        viewModel: SettingsViewModel(),
        workspaceStore: WorkspaceStore()
    )
    .frame(width: 750, height: 800)
}
