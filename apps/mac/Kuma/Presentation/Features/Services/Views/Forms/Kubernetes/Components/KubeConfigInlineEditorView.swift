import SwiftUI

public struct KubeConfigInlineEditorView: View {
    @Bindable var viewModel: KubeConfigViewModel
    let onDismiss: () -> Void
    let onSaveSuccess: () -> Void

    @State private var sourceMode: KumaDualSourceMode = .chooseFile
    @State private var draftPath: String = ""
    @State private var draftYAML: String = ""

    private var saveDisabled: Bool {
        viewModel.isSaveDisabled(sourceMode: sourceMode, draftPath: draftPath, draftYAML: draftYAML)
    }

    public init(
        viewModel: KubeConfigViewModel,
        onDismiss: @escaping () -> Void,
        onSaveSuccess: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onSaveSuccess = onSaveSuccess
    }

    public var body: some View {
        KumaFormInlinePanel(
            headerTitle: viewModel.editingKubeConfigID == nil ? "New Kube Config" : "Edit Kube Config",
            headerIcon: "doc.text.fill",
            closeAccessibilityLabel: "Close kube config editor",
            primaryTitle: sourceMode == .pasteYAML ? "Save" : "Save",
            primaryDisabled: saveDisabled,
            showsCommitFooter: sourceMode == .pasteYAML || !draftPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            showsCancelInFooter: sourceMode == .pasteYAML,
            onCancel: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    onDismiss()
                }
            },
            onPrimary: {
                commitDraftsToViewModel()
                Task {
                    await viewModel.saveConfig(sourceMode: sourceMode)
                    onSaveSuccess()
                }
            }
        ) {
            VStack(alignment: .leading, spacing: KumaSpacing.md) {
                KumaTextField(label: "Name", value: $viewModel.newKubeConfigName, placeholder: "Staging Cluster")

                Divider().opacity(0.3)

                KubeConfigEditorExpandedContent(
                    sourceMode: $sourceMode,
                    draftPath: $draftPath,
                    draftYAML: $draftYAML
                )
            }
            .padding(.top, KumaSpacing.xs)
            .padding(.bottom, KumaSpacing.xs)
        }
        .onAppear { syncDraftsFromViewModel() }
        .onChange(of: draftPath) { _, newPath in
            guard sourceMode == .chooseFile else { return }
            let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if viewModel.newKubeConfigName.isEmpty {
                viewModel.newKubeConfigName = (trimmed as NSString).lastPathComponent
            }
        }
    }

    private func syncDraftsFromViewModel() {
        draftPath = viewModel.newKubeConfigSourcePath
        draftYAML = viewModel.newKubeConfigContent
        sourceMode = viewModel.inferredSourceMode(path: draftPath, yaml: draftYAML)
    }

    private func commitDraftsToViewModel() {
        switch sourceMode {
        case .chooseFile:
            viewModel.newKubeConfigSourcePath = draftPath.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.newKubeConfigContent = ""
        case .pasteYAML:
            viewModel.newKubeConfigContent = draftYAML
            viewModel.newKubeConfigSourcePath = ""
        }
    }
}
