import SwiftUI

@main
struct KumaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator()
    @State private var workspaceStore = WorkspaceStore()
    @State private var serviceStateStore = ServiceStateStore()

    var body: some Scene {
        // ─── Scene 1: Main Workspace Window ───────────────────────────
        // Default root window scene opened by macOS
        WindowGroup(id: "main-workspace") {
            ContentView()
                .environment(coordinator)
                .environment(workspaceStore)
                .environment(serviceStateStore)
                .kumaMainWorkspaceChrome()
                .onAppear {
                    KumaLogFont.registerBundledFonts()
                    SystemActivityLogRecording.install(LiveLogRecordingBridge())
                    appDelegate.serviceStateStore = serviceStateStore
                    if !SingleInstanceGuard.isTestingEnvironment {
                        RunSpool.purgeAll()
                    }
                    serviceStateStore.bindExecutionSupervisor()
                }
        }
        .defaultSize(width: 1100, height: 750)
        .windowResizability(.contentMinSize)
        .kumaDisabledWindowRestoration()
        .commands {
            KumaCommands(coordinator: coordinator, workspaceStore: workspaceStore)
        }

        // ─── Scene 2: Onboarding Wizard Window ─────────────────────────
        // Compact plain utility window, floating, suppressed by default
        Window("Welcome to Kuma", id: "onboarding") {
            OnboardingWizardView {
                coordinator.transitionTo(.mainWorkspace)
            }
            .environment(coordinator)
            .kumaOnboardingWindowDragSupport()
        }
        .windowResizability(.contentSize)
        .kumaOnboardingWindowChrome()
    }
}


