import SwiftUI

struct KubeConfigEditorExpandedContent: View {
    @Binding var sourceMode: KumaDualSourceMode
    @Binding var draftPath: String
    @Binding var draftYAML: String

    var body: some View {
        KumaSourceField(
            label: "Config",
            mode: $sourceMode,
            path: $draftPath,
            text: $draftYAML,
            pasteTabLabel: "Paste Config",
            filePrompt: KubeConfigFilePickerSupport.defaultConfigPlaceholder,
            editorPlaceholder: "Paste kubeconfig YAML…",
            editorMinHeight: 120,
            editorMaxHeight: 160,
            allowedContentTypes: KubeConfigFilePickerSupport.allowedContentTypes,
            allowsOtherFileTypes: true,
            browseDirectory: { KubeConfigFilePickerSupport.browseDirectoryURL(for: $0) }
        )
    }
}
