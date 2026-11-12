import SwiftUI

public struct ImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let backup: DataPortService.KumaBackup
    public let fileName: String
    public let existingWorkspaceIDs: Set<UUID>
    public let onConfirmImport: (_ selectedWorkspaceIDs: Set<UUID>, _ selectedServiceIDs: Set<UUID>) -> Void

    @State private var tableRows: [FullImportTableRow] = []
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var focusedRowID: UUID? = nil
    @State private var searchText: String = ""

    public init(
        backup: DataPortService.KumaBackup,
        fileName: String,
        existingWorkspaceIDs: Set<UUID>,
        onConfirmImport: @escaping (Set<UUID>, Set<UUID>) -> Void
    ) {
        self.backup = backup
        self.fileName = fileName
        self.existingWorkspaceIDs = existingWorkspaceIDs
        self.onConfirmImport = onConfirmImport
    }

    private var filteredRows: [FullImportTableRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return tableRows }
        return tableRows.filter { row in
            row.serviceName.lowercased().contains(query) ||
            row.workspaceName.lowercased().contains(query) ||
            row.providerCategory.sidebarLabel.lowercased().contains(query) ||
            row.target.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ImportPreviewHeaderView(
                title: "Import Configuration",
                subtitle: "\(fileName) • \(backup.workspaces.count) workspaces, \(backup.services.count) services",
                searchPrompt: "Search services",
                searchText: $searchText
            )

            Divider().opacity(0.4)

            FullImportTableView(
                rows: filteredRows,
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
                    confirmAndImport()
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

    private func confirmAndImport() {
        let selectedRows = tableRows.filter { selectedRowIDs.contains($0.id) }
        let selectedWS = Set(selectedRows.map(\.workspaceID))
        onConfirmImport(selectedWS, selectedRowIDs)
    }

    private func buildRows() {
        var rows: [FullImportTableRow] = []
        let workspaceMap = Dictionary(uniqueKeysWithValues: backup.workspaces.map { ($0.id, $0) })

        for service in backup.services {
            let ws = service.workspaceID.flatMap { workspaceMap[$0] }
            let wsName = ws?.name ?? "Default Workspace"
            let wsID = ws?.id ?? (backup.workspaces.first?.id ?? UUID())
            let isExisting = existingWorkspaceIDs.contains(wsID)
            let provider = backup.providers.first(where: { $0.serviceID == service.id })
            let category = provider?.category ?? .docker
            let targetString = provider?.resolvedTarget ?? ""
            let ports = backup.portMappings.filter { $0.providerID == provider?.id || $0.providerID == service.id }

            rows.append(FullImportTableRow(
                id: service.id,
                serviceName: service.name,
                serviceDescription: service.description,
                workspaceName: wsName,
                workspaceID: wsID,
                providerCategory: category,
                target: targetString,
                isExistingWorkspace: isExisting,
                provider: provider,
                portMappings: ports
            ))
        }
        self.tableRows = rows
        self.selectedRowIDs = Set(rows.map(\.id))
        self.focusedRowID = rows.first?.id
    }
}
