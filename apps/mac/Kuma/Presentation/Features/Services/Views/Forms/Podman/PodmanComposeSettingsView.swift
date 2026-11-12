import SwiftUI

public struct PodmanComposeSettingsView: View {
    @Binding public var yamlConfig: String
    @Binding public var composeFilePath: String
    public var isLocked: Bool
    public var bindingIdentity: UUID?
    public var onSave: () -> Void

    public init(
        yamlConfig: Binding<String>,
        composeFilePath: Binding<String>,
        isLocked: Bool = false,
        bindingIdentity: UUID? = nil,
        onSave: @escaping () -> Void = {}
    ) {
        self._yamlConfig = yamlConfig
        self._composeFilePath = composeFilePath
        self.isLocked = isLocked
        self.bindingIdentity = bindingIdentity
        self.onSave = onSave
    }

    public var body: some View {
        ComposeSettingsView(
            filePrompt: "~/path/to/compose.yml",
            editorPlaceholder: "version: '3.8'\nservices:\n  app:\n    image: quay.io/podman/hello\n    ports:\n      - \"8080:8080\"",
            yamlConfig: $yamlConfig,
            composeFilePath: $composeFilePath,
            isLocked: isLocked,
            bindingIdentity: bindingIdentity,
            onSave: onSave
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var yaml = "version: '3.8'\nservices:\n  api:\n    image: node:18-alpine"
        @State private var composePath = ""

        var body: some View {
            PodmanComposeSettingsView(yamlConfig: $yaml, composeFilePath: $composePath)
                .padding()
                .frame(width: 500)
        }
    }
    return PreviewWrapper()
}
