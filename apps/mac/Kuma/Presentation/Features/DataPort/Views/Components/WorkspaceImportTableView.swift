import SwiftUI

public struct WorkspaceImportTableView: View {
    public let rows: [ServiceImportRow]
    public let renamedOverrides: [UUID: String]
    @Binding public var selectedRowIDs: Set<UUID>
    @Binding public var focusedRowID: UUID?

    public init(
        rows: [ServiceImportRow],
        renamedOverrides: [UUID: String],
        selectedRowIDs: Binding<Set<UUID>>,
        focusedRowID: Binding<UUID?>
    ) {
        self.rows = rows
        self.renamedOverrides = renamedOverrides
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
                    Text(renamedOverrides[row.id] ?? row.serviceName)
                        .font(.system(size: 12, weight: .semibold))
                    if let desc = row.serviceDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Provider") { row in
                Text(row.providerCategory.sidebarLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
            .width(min: 100, ideal: 120)

            TableColumn("Config / Target") { row in
                Text(row.target.isEmpty ? "—" : row.target)
                    .font(.system(size: 11, design: isMonospacedTarget(for: row.providerCategory) ? .monospaced : .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Ports") { row in
                ImportPortsBadgeView(portMappings: row.portMappings, maxVisible: 2)
            }
            .width(min: 110, ideal: 140, max: 170)

            TableColumn("Action") { row in
                if row.hasConflict {
                    Text("Auto-Rename")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                } else {
                    Text("Import")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }
            .width(85)
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
