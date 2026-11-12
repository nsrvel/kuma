import SwiftUI

public struct WorkspaceImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let backup: DataPortService.KumaBackup
    public let fileName: String
    public let targetWorkspaceName: String
    public let targetWorkspaceID: UUID
    public let existingServiceNames: Set<String>
    public let onConfirmImport: (_ selectedServiceIDs: Set<UUID>, _ resolvedNames: [UUID: String]) -> Void

    @State private var tableRows: [ServiceImportRow] = []
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var renamedOverrides: [UUID: String] = [:]
    @State private var focusedRowID: UUID? = nil
    @State private var searchText: String = ""

    public init(
        backup: DataPortService.KumaBackup,
        fileName: String,
        targetWorkspaceName: String,
        targetWorkspaceID: UUID,
        existingServiceNames: Set<String> = [],
        onConfirmImport: @escaping (Set<UUID>, [UUID: String]) -> Void
    ) {
        self.backup = backup
        self.fileName = fileName
        self.targetWorkspaceName = targetWorkspaceName
        self.targetWorkspaceID = targetWorkspaceID
        self.existingServiceNames = existingServiceNames
        self.onConfirmImport = onConfirmImport
    }

    private var filteredRows: [ServiceImportRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tableRows }
        return tableRows.filter { row in
            row.serviceName.lowercased().contains(query) ||
            row.providerCategory.sidebarLabel.lowercased().contains(query) ||
            row.target.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ImportPreviewHeaderView(
                title: "Import Services into “\(targetWorkspaceName)”",
                subtitle: "\(fileName) • \(backup.services.count) services found in backup",
                searchPrompt: "Search services",
                searchText: $searchText
            )

            Divider().opacity(0.4)

            WorkspaceImportTableView(
                rows: filteredRows,
                renamedOverrides: renamedOverrides,
                selectedRowIDs: $selectedRowIDs,
                focusedRowID: $focusedRowID
            )
            .frame(minHeight: 320, idealHeight: 400, maxHeight: .infinity)

            Divider().opacity(0.4)

            ImportPreviewFooterView(
                selectedCount: selectedRowIDs.count,
                totalCount: tableRows.count,
                filteredCount: filteredRows.count,
                onToggleSelectAll: toggleSelectAll,
                onCancel: { dismiss() },
                onImport: {
                    onConfirmImport(selectedRowIDs, renamedOverrides)
                    dismiss()
                }
            )
        }
        .frame(minWidth: 780, idealWidth: 860, maxWidth: 1200, minHeight: 460, idealHeight: 540, maxHeight: 800)
        .onAppear { buildRows() }
    }

    private func toggleSelectAll() {
        if selectedRowIDs.count == filteredRows.count && !filteredRows.isEmpty {
            selectedRowIDs.removeAll()
        } else {
            selectedRowIDs = Set(filteredRows.map(\.id))
        }
    }

    private func buildRows() {
        var rows: [ServiceImportRow] = []
        var renames: [UUID: String] = [:]

        for service in backup.services {
            let provider = backup.providers.first(where: { $0.serviceID == service.id })
            let category = provider?.category ?? .docker
            let targetString = provider?.resolvedTarget ?? ""
            let ports = backup.portMappings.filter { $0.providerID == provider?.id || $0.providerID == service.id }

            let hasConflict = existingServiceNames.contains(service.name.lowercased())
            if hasConflict {
                renames[service.id] = "\(service.name) (Imported)"
            }

            rows.append(ServiceImportRow(
                id: service.id,
                serviceName: service.name,
                serviceDescription: service.description,
                providerCategory: category,
                target: targetString,
                hasConflict: hasConflict,
                provider: provider,
                portMappings: ports
            ))
        }
        self.tableRows = rows
        self.renamedOverrides = renames
        self.selectedRowIDs = Set(rows.map(\.id))
        self.focusedRowID = rows.first?.id
    }
}
