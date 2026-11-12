import SwiftUI

public struct FullImportTableView: View {
    public let rows: [FullImportTableRow]
    @Binding public var selectedRowIDs: Set<UUID>
    @Binding public var focusedRowID: UUID?

    public init(
        rows: [FullImportTableRow],
        selectedRowIDs: Binding<Set<UUID>>,
        focusedRowID: Binding<UUID?>
    ) {
        self.rows = rows
        self._selectedRowIDs = selectedRowIDs
        self._focusedRowID = focusedRowID
    }

    public var body: some View {
        Table(rows, selection: $focusedRowID) {
            TableColumn("") { row in
                Toggle("", isOn: Binding(
                    get: { selectedRowIDs.contains(row.id) },
                    set: { isSelected in
                        if isSelected {
                            selectedRowIDs.insert(row.id)
                        } else {
                            selectedRowIDs.remove(row.id)
                        }
                    }
                ))
                .labelsHidden()
                .controlSize(.mini)
            }
            .width(28)

            TableColumn("Name") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.serviceName)
                        .font(.system(size: 12, weight: .semibold))
                    if let desc = row.serviceDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 140, ideal: 180)

            TableColumn("Workspace") { row in
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(row.workspaceName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 130)

            TableColumn("Provider") { row in
                Text(row.providerCategory.sidebarLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
            .width(min: 95, ideal: 115)

            TableColumn("Config / Target") { row in
                Text(row.target.isEmpty ? "—" : row.target)
                    .font(.system(size: 11, design: isMonospacedTarget(for: row.providerCategory) ? .monospaced : .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 200)

            TableColumn("Ports") { row in
                ImportPortsBadgeView(portMappings: row.portMappings, maxVisible: 2)
            }
            .width(min: 110, ideal: 140, max: 170)

            TableColumn("Status") { row in
                let isMerge = row.isExistingWorkspace
                Text(isMerge ? "Merge" : "New")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isMerge ? .orange : .green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isMerge ? Color.orange : Color.green).opacity(0.12), in: Capsule())
            }
            .width(60)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func isMonospacedTarget(for category: ProviderCategory) -> Bool {
        switch category {
        case .docker, .podman, .kubernetes, .shell, .ssh: return true
        default: return false
        }
    }
}
