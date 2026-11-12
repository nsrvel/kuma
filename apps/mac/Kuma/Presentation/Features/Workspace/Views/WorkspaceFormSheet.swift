import SwiftUI
import AppKit

public enum WorkspaceFormMode: Equatable {
    case create
    case edit(Workspace)
}

public struct WorkspaceFormSheet: View {
    @Bindable var store: WorkspaceStore
    let mode: WorkspaceFormMode
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var selectedImagePath: String? = nil
    @State private var selectedImageURL: URL? = nil
    @State private var errorMessage: String? = nil

    public init(store: WorkspaceStore, mode: WorkspaceFormMode, isPresented: Binding<Bool>) {
        self.store = store
        self.mode = mode
        self._isPresented = isPresented

        switch mode {
        case .create:
            _name = State(initialValue: "")
        case .edit(let ws):
            _name = State(initialValue: ws.name)
            _selectedImagePath = State(initialValue: ws.imagePath)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Dialog Header (Centered Title - Apple HIG macOS Standard)
            Text(mode == .create ? "New Workspace" : "Workspace Settings")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.primary)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .opacity(0.4)

            // 2. Form Body
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 16) {
                    WorkspaceAvatarPickerView(
                        name: name.isEmpty ? "Workspace" : name,
                        selectedImagePath: $selectedImagePath,
                        selectedImageURL: $selectedImageURL
                    )

                    KumaTextField(
                        label: "Workspace Name",
                        value: $name,
                        placeholder: "My Workspace",
                        autoFocus: true,
                        onSubmit: {
                            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveChanges()
                            }
                        }
                    )
                }
                .padding(.top, 8)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                        .padding(.top, -8)
                }

                if case .edit(let ws) = mode, store.workspaces.count > 1 {
                    Divider().opacity(0.3)

                    WorkspaceFormDeleteRow {
                        isPresented = false
                        AlertService.shared.confirmDelete(
                            title: "Delete Workspace?",
                            message: "“\(ws.name)” and all its services will be permanently deleted.",
                            confirmTitle: "Delete"
                        ) {
                            store.deleteWorkspace(ws)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()
                .opacity(0.4)

            // 3. Dialog Footer (Native macOS Bottom-Right Action Buttons)
            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(mode == .create ? "Add" : "Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: KumaTheme.Workspace.formSheetWidth)
        .frame(minHeight: KumaTheme.Workspace.formSheetMinHeightCompact)
    }

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty"
            return
        }

        switch mode {
        case .create:
            let newWS = store.addWorkspace(name: trimmedName, imagePath: selectedImageURL?.path(percentEncoded: false) ?? selectedImagePath)
            store.selectWorkspace(newWS)
        case .edit(var ws):
            ws.name = trimmedName
            if selectedImagePath == nil && selectedImageURL == nil {
                // User removed photo
                if let oldPath = ws.imagePath {
                    WorkspaceImageStore.shared.deleteImage(for: oldPath)
                }
                ws.imagePath = nil
            }
            ws.updatedAt = Date()
            store.updateWorkspace(ws, newExternalImageURL: selectedImageURL)
        }
        isPresented = false
    }
}

#Preview {
    WorkspaceFormSheet(
        store: WorkspaceStore(),
        mode: .create,
        isPresented: .constant(true)
    )
}
