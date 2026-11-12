import SwiftUI
import UniformTypeIdentifiers

/// Shared compose YAML editor for Docker and Podman providers.
public struct ComposeSettingsView: View {
    public let filePrompt: String
    public let editorPlaceholder: String
    @Binding public var yamlConfig: String
    @Binding public var composeFilePath: String
    public var isLocked: Bool
    public var onSave: () -> Void
    /// When this changes (e.g. another provider), tab mode is re-inferred from path/YAML.
    public var bindingIdentity: UUID?

    @State private var sourceMode: KumaDualSourceMode = .chooseFile

    public init(
        filePrompt: String,
        editorPlaceholder: String,
        yamlConfig: Binding<String>,
        composeFilePath: Binding<String>,
        isLocked: Bool = false,
        bindingIdentity: UUID? = nil,
        onSave: @escaping () -> Void = {}
    ) {
        self.filePrompt = filePrompt
        self.editorPlaceholder = editorPlaceholder
        self._yamlConfig = yamlConfig
        self._composeFilePath = composeFilePath
        self.isLocked = isLocked
        self.bindingIdentity = bindingIdentity
        self.onSave = onSave
    }

    public var body: some View {
        KumaSourceField(
            label: "Compose File",
            mode: $sourceMode,
            path: pathBinding,
            text: yamlBinding,
            filePrompt: filePrompt,
            editorPlaceholder: editorPlaceholder,
            allowedContentTypes: ComposeFileTypes.allowed,
            isLocked: isLocked
        )
        .onAppear { syncModeFromBindings() }
        .onChange(of: bindingIdentity) { _, _ in syncModeFromBindings() }
        .onChange(of: composeFilePath) { _, _ in syncModeFromBindings() }
        .onChange(of: yamlConfig) { _, _ in syncModeFromBindings() }
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { composeFilePath },
            set: { newPath in
                let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
                composeFilePath = trimmed
                if !trimmed.isEmpty, !yamlConfig.isEmpty {
                    yamlConfig = ""
                }
                onSave()
            }
        )
    }

    private var yamlBinding: Binding<String> {
        Binding(
            get: { yamlConfig },
            set: { newYAML in
                yamlConfig = newYAML
                if !newYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !composeFilePath.isEmpty {
                    composeFilePath = ""
                }
                onSave()
            }
        )
    }

    private func syncModeFromBindings() {
        sourceMode = KumaDualSourceMode.inferred(
            path: composeFilePath,
            text: yamlConfig,
            fallback: .chooseFile
        )
    }
}

public enum ComposeFileTypes {
    public static let allowed: [UTType] = {
        var types: [UTType] = []
        if let yml = UTType(filenameExtension: "yml") { types.append(yml) }
        if let yaml = UTType(filenameExtension: "yaml") { types.append(yaml) }
        types.append(.plainText)
        return types
    }()
}
