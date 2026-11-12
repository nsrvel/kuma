import SwiftUI

public struct ImportPreviewFooterView: View {
    public let selectedCount: Int
    public let totalCount: Int
    public let filteredCount: Int
    public let onToggleSelectAll: () -> Void
    public let onCancel: () -> Void
    public let onImport: () -> Void

    public init(
        selectedCount: Int,
        totalCount: Int,
        filteredCount: Int,
        onToggleSelectAll: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onImport: @escaping () -> Void
    ) {
        self.selectedCount = selectedCount
        self.totalCount = totalCount
        self.filteredCount = filteredCount
        self.onToggleSelectAll = onToggleSelectAll
        self.onCancel = onCancel
        self.onImport = onImport
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(selectedCount == filteredCount && filteredCount > 0 ? "Deselect All" : "Select All") {
                onToggleSelectAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)

            Spacer()

            Text("\(selectedCount) of \(totalCount) selected\(filteredCount != totalCount ? " (\(filteredCount) matching)" : "")")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Import") {
                onImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}
