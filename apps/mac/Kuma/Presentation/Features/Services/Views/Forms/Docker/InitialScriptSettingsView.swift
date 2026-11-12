import SwiftUI

// MARK: - InitialScriptSettingsView

/// Pre-startup shell script: file on disk or inline snippet.
public struct InitialScriptSettingsView: View {
    @Binding public var initialScript: String
    @Binding public var initialScriptPath: String
    public var isLocked: Bool
    public var onSave: () -> Void

    @State private var sourceMode: KumaDualSourceMode = .chooseFile

    public init(
        initialScript: Binding<String>,
        initialScriptPath: Binding<String>,
        isLocked: Bool = false,
        onSave: @escaping () -> Void = {}
    ) {
        self._initialScript = initialScript
        self._initialScriptPath = initialScriptPath
        self.isLocked = isLocked
        self.onSave = onSave
    }

    public var body: some View {
        KumaSourceField(
            label: "Startup Script",
            mode: $sourceMode,
            path: pathBinding,
            text: scriptBinding,
            pasteTabLabel: "Paste Script",
            filePrompt: "/path/to/script.sh",
            editorPlaceholder: "#!/bin/bash\n",
            editorMinHeight: 120,
            editorMaxHeight: 160,
            allowedContentTypes: KumaScriptFileSupport.allowedTypes,
            isLocked: isLocked
        )
        .onAppear { syncModeFromBindings() }
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { initialScriptPath },
            set: { newPath in
                let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
                initialScriptPath = trimmed
                if !trimmed.isEmpty, !initialScript.isEmpty {
                    initialScript = ""
                }
                onSave()
            }
        )
    }

    private var scriptBinding: Binding<String> {
        Binding(
            get: { initialScript },
            set: { newScript in
                initialScript = newScript
                if !newScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !initialScriptPath.isEmpty {
                    initialScriptPath = ""
                }
                onSave()
            }
        )
    }

    private func syncModeFromBindings() {
        sourceMode = KumaDualSourceMode.inferred(
            path: initialScriptPath,
            text: initialScript,
            fallback: .pasteYAML
        )
    }
}
