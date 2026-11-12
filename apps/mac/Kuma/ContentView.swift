import SwiftUI

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(WorkspaceStore.self) private var workspaceStore
    @State private var sidebarViewModel = SidebarViewModel.makeDefault()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var settingsViewModel = SettingsViewModel()
    @State private var showCreateServiceSheet: Bool = false
    @State private var droppedBackup: DataPortService.KumaBackup? = nil
    @State private var droppedFileName: String = ""
    @State private var isDragTargetActive: Bool = false

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(viewModel: sidebarViewModel, workspaceStore: workspaceStore)
            } detail: {
                detailView(for: sidebarViewModel.selectedID)
            }
            .navigationSplitViewStyle(.prominentDetail)

            // Finder Drop Target Overlay (Instant Zero-Delay Full Window Coverage)
            if isDragTargetActive {
                FinderDropTargetOverlay()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let fileURL = urls.first, fileURL.pathExtension.lowercased() == "json" else {
                return false
            }
            do {
                let data = try Data(contentsOf: fileURL)
                let targetWS = workspaceStore.activeWorkspace?.id
                let backup = try DataPortService.parseAnyBackup(from: data, targetWorkspaceID: targetWS)
                self.droppedBackup = backup
                self.droppedFileName = fileURL.lastPathComponent
                return true
            } catch {
                AlertService.shared.showError(
                    title: "Invalid Backup File",
                    message: "Failed to read '\(fileURL.lastPathComponent)': \(error.localizedDescription)"
                )
                return false
            }
        } isTargeted: { targeted in
            guard isDragTargetActive != targeted else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isDragTargetActive = targeted
            }
        }
        .sheet(item: $droppedBackup) { backup in
            ImportPreviewSheet(
                backup: backup,
                fileName: droppedFileName,
                existingWorkspaceIDs: Set(workspaceStore.workspaces.map(\.id)),
                onConfirmImport: { selectedWorkspaces, selectedServices in
                    Task {
                        do {
                            let dataPort = DataPortRepository()
                            try await dataPort.importSelective(from: backup, selectedWorkspaceIDs: selectedWorkspaces, selectedServiceIDs: selectedServices)
                            workspaceStore.loadFromDatabase()
                        } catch {
                            AlertService.shared.showError(
                                title: "Import Failed",
                                message: error.localizedDescription
                            )
                        }
                    }
                }
            )
        }

        .onReceive(NotificationCenter.default.publisher(for: .kumaOpenSettings)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                sidebarViewModel.selectedID = .stable("settings")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kumaCreateServiceRequested)) { _ in
            showCreateServiceSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .kumaOpenOnboarding)) { _ in
            openWindow(id: "onboarding")
            dismissWindow(id: "main-workspace")
        }
        .task {
            if coordinator.currentPhase == .onboarding {
                openWindow(id: "onboarding")
                dismissWindow(id: "main-workspace")
            }
        }
        .sheet(isPresented: $showCreateServiceSheet) {
            if let activeWorkspace = workspaceStore.activeWorkspace {
                CreateServiceSheet(
                    workspaceID: activeWorkspace.id,
                    creationDefaults: createServiceDefaultsForCurrentSidebar()
                ) {
                    NotificationCenter.default.post(name: .kumaServiceCreated, object: nil)
                }
            }
        }
        .sheet(isPresented: Bindable(workspaceStore).showCreateSheet) {
            WorkspaceFormSheet(store: workspaceStore, mode: .create, isPresented: Bindable(workspaceStore).showCreateSheet)
        }
        .sheet(item: Bindable(workspaceStore).workspaceToEdit) { ws in
            WorkspaceFormSheet(store: workspaceStore, mode: .edit(ws), isPresented: Binding(
                get: { workspaceStore.workspaceToEdit != nil },
                set: { if !$0 { workspaceStore.workspaceToEdit = nil } }
            ))
        }
        .withKumaAlerts()
    }


    private func createServiceDefaultsForCurrentSidebar() -> CreateServiceCreationDefaults {
        let selected = sidebarViewModel.selectedID
        return CreateServiceCreationDefaults(
            starOnCreate: selected == .stable("starred-services"),
            initialGroupID: sidebarViewModel.groupIDForSelectedRow(selected)
        )
    }

    @ViewBuilder
    private func detailView(for selectedID: UUID?) -> some View {
        if selectedID == .stable("settings") {
            SettingsView(viewModel: settingsViewModel, workspaceStore: workspaceStore)
        } else if let activeWorkspace = workspaceStore.activeWorkspace {

            WorkspaceServicesDeckHost(
                workspaceID: activeWorkspace.id,
                selectedSidebarID: selectedID,
                sidebarViewModel: sidebarViewModel
            )
            .id(activeWorkspace.id)
        } else {
            KumaEmptyStateView(
                iconName: "square.stack.3d.up.slash",
                title: "No Active Workspace",
                description: "Select or create a workspace from the sidebar to view your services."
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(AppCoordinator(initialPhase: .mainWorkspace))
        .environment(WorkspaceStore())
}

