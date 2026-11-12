import SwiftUI
import UniformTypeIdentifiers

extension ServicesDeckView {
    public func exportCurrentWorkspace() {
        let wsName = workspaceStore.workspaces.first(where: { $0.id == workspaceID })?.name ?? "workspace"
        let sanitizedName = wsName.lowercased().replacingOccurrences(of: " ", with: "-")
        let panel = NSSavePanel()
        panel.title = "Export Workspace (\(wsName))"
        panel.nameFieldStringValue = "\(sanitizedName)-services-\(DataPortService.backupDateString).json"
        panel.allowedContentTypes = [.json]

        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    self.performWorkspaceExport(to: url)
                }
            }
            return
        }

        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                self.performWorkspaceExport(to: url)
            }
        }
    }

    public func performWorkspaceExport(to url: URL) {
        Task {
            do {
                let dataPort = DataPortRepository()
                let backup = try await dataPort.exportData(scope: .workspace(workspaceID))
                let data = try DataPortService.encodeBackup(backup)
                try data.write(to: url, options: .atomic)
            } catch {
                alertMessage = "Failed to export workspace: \(error.localizedDescription)"
            }
        }
    }

    public func promptImportFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Services into Workspace"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]

        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    self.processWorkspaceImportUrl(url)
                }
            }
            return
        }

        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                self.processWorkspaceImportUrl(url)
            }
        }
    }

    public func processWorkspaceImportUrl(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let backup = try DataPortService.parseAnyBackup(from: data, targetWorkspaceID: workspaceID)
            self.pendingImportBackup = backup
            self.pendingImportFileName = url.lastPathComponent
        } catch {
            alertMessage = "Failed to read backup file: \(error.localizedDescription)"
        }
    }

    public func executeImport(backup: DataPortService.KumaBackup, selectedServiceIDs: Set<UUID>, resolvedNames: [UUID: String]) {
        Task {
            do {
                let dataPort = DataPortRepository()
                try await dataPort.importIntoWorkspace(
                    targetWorkspaceID: workspaceID,
                    backup: backup,
                    selectedServiceIDs: selectedServiceIDs,
                    resolvedNames: resolvedNames
                )
                viewModel.loadWorkspace(workspaceID: workspaceID)
                workspaceStore.loadFromDatabase()
            } catch {
                alertMessage = "Failed to import services: \(error.localizedDescription)"
            }
        }
    }
}
