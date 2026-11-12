import SwiftUI

/// Destructive delete row for workspace edit sheet (matches Settings data section pattern).
struct WorkspaceFormDeleteRow: View {
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Delete Workspace")
                    .font(KumaFont.body)
                    .foregroundStyle(.red)
                Text("Permanently remove this workspace and all services.")
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Delete", action: onDelete)
                .buttonStyle(.bordered)
                .tint(.red)
        }
    }
}
