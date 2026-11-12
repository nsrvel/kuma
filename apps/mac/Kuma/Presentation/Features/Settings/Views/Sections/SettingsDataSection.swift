import SwiftUI
import UniformTypeIdentifiers

public struct SettingsDataSection: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var workspaceStore: WorkspaceStore

    @State private var showResetConfirmation = false
    @State private var showResetSettingsConfirmation = false
    @State private var loadedBackup: DataPortService.KumaBackup? = nil
    @State private var pendingImportFileName: String = ""
    @State private var alertMessage: String? = nil
    @State private var isProcessing = false

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    public init(viewModel: SettingsViewModel, workspaceStore: WorkspaceStore) {
        self.viewModel = viewModel
        self.workspaceStore = workspaceStore
    }

    public var body: some View {
        KumaFormSection(
            icon: "internaldrive.fill",
            title: "Data"
        ) {
            VStack(alignment: .leading, spacing: KumaSpacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Backup")
                            .font(KumaFont.body)
                        Text("Export workspaces, services, and configuration to JSON.")
                            .font(KumaFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Export") {
                        exportData()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }

                Divider().opacity(0.3)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Backup")
                            .font(KumaFont.body)
                        Text("Restore workspaces and configuration from a JSON backup.")
                            .font(KumaFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Import") {
                        promptImportFile()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }

                Divider().opacity(0.3)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Settings to Default")
                            .font(KumaFont.body)
                            .foregroundStyle(.primary)
                        Text("Restore preferences without affecting workspaces.")
                            .font(KumaFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") {
                        showResetSettingsConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }

                Divider().opacity(0.3)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset All Data")
                            .font(KumaFont.body)
                            .foregroundStyle(.red)
                        Text("Permanently delete all workspaces and services.")
                            .font(KumaFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset All") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isProcessing)
                }
            }
        }
        .sheet(item: $loadedBackup) { backup in
            ImportPreviewSheet(
                backup: backup,
                fileName: pendingImportFileName,
                existingWorkspaceIDs: Set(workspaceStore.workspaces.map(\.id)),
                onConfirmImport: { selectedWorkspaces, selectedServices in
                    loadedBackup = nil
                    executeSelectiveImport(
                        backup: backup,
                        selectedWorkspaces: selectedWorkspaces,
                        selectedServices: selectedServices
                    )
                }
            )
        }
        .alert("Backup & Restore", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            "Reset Settings?",
            isPresented: $showResetSettingsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Settings", role: .destructive) {
                viewModel.resetSettingsToDefault()
                alertMessage = "All preferences have been reset to defaults."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All preferences and tool paths will be reset to defaults. Workspaces and services will not be affected.")
        }
        .confirmationDialog(
            "Reset All Data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Data", role: .destructive) {
                resetData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All workspaces, services, and data will be permanently deleted.")
        }
    }

    private func exportData() {
        SettingsDataPanelPresenter.presentSavePanel(
            title: "Export Kuma Backup",
            defaultFileName: "kuma-backup-\(DataPortService.backupDateString).json"
        ) { url in
            self.performExport(to: url)
        }
    }

    private func performExport(to url: URL) {
        isProcessing = true
        Task {
            do {
                let dataPort = DataPortRepository()
                let backup = try await dataPort.exportAll()
                let data = try DataPortService.encodeBackup(backup)
                try data.write(to: url, options: .atomic)
                isProcessing = false
                alertMessage = "Backup exported to \(url.lastPathComponent)."
            } catch {
                isProcessing = false
                alertMessage = "Failed to export data: \(error.localizedDescription)"
            }
        }
    }

    private func promptImportFile() {
        SettingsDataPanelPresenter.presentOpenPanel(
            title: "Import Kuma Backup"
        ) { url in
            self.processImportUrl(url)
        }
    }

    private func processImportUrl(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let backup = try DataPortService.decodeBackup(from: data)
            self.loadedBackup = backup
            self.pendingImportFileName = url.lastPathComponent
        } catch {
            alertMessage = "Failed to read backup file: \(error.localizedDescription)"
        }
    }

    private func executeSelectiveImport(
        backup: DataPortService.KumaBackup,
        selectedWorkspaces: Set<UUID>,
        selectedServices: Set<UUID>
    ) {
        isProcessing = true
        Task {
            do {
                let dataPort = DataPortRepository()
                try await dataPort.importSelective(
                    from: backup,
                    selectedWorkspaceIDs: selectedWorkspaces,
                    selectedServiceIDs: selectedServices
                )

                workspaceStore.loadFromDatabase()
                isProcessing = false
                alertMessage = "Backup imported (\(selectedWorkspaces.count) workspaces, \(selectedServices.count) services restored)."
            } catch {
                isProcessing = false
                alertMessage = "Failed to import backup: \(error.localizedDescription)"
            }
        }
    }

    private func resetData() {
        isProcessing = true
        Task {
            await DataPortService.resetAllAppStorage()
            workspaceStore.loadFromDatabase()
            coordinator.resetToOnboarding()
            isProcessing = false
            openWindow(id: "onboarding")
            dismissWindow(id: "main-workspace")
        }
    }
}
