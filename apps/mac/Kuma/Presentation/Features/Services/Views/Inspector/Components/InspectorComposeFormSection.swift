import SwiftUI

public struct InspectorComposeFormSection: View {
    @Binding public var provider: Provider
    public let isLocked: Bool
    public let isPodman: Bool
    public let onFieldChanged: () -> Void

    public var body: some View {
        KumaFormSection(icon: "shippingbox.fill", title: "Configuration") {
            VStack(alignment: .leading, spacing: KumaSpacing.md) {
                if isPodman {
                    PodmanComposeSettingsView(
                        yamlConfig: optionalStringBinding(\.yamlConfig),
                        composeFilePath: optionalStringBinding(\.composeFilePath),
                        isLocked: isLocked,
                        bindingIdentity: provider.id,
                        onSave: onFieldChanged
                    )
                } else {
                    DockerComposeSettingsView(
                        yamlConfig: optionalStringBinding(\.yamlConfig),
                        composeFilePath: optionalStringBinding(\.composeFilePath),
                        isLocked: isLocked,
                        bindingIdentity: provider.id,
                        onSave: onFieldChanged
                    )
                }

                InitialScriptSettingsView(
                    initialScript: optionalStringBinding(\.initialScript),
                    initialScriptPath: optionalStringBinding(\.initialScriptPath),
                    isLocked: isLocked,
                    onSave: onFieldChanged
                )
            }
            .disabled(isLocked)
        }
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<Provider, String?>) -> Binding<String> {
        Binding(
            get: { provider[keyPath: keyPath] ?? "" },
            set: {
                provider[keyPath: keyPath] = $0.isEmpty ? nil : $0
                onFieldChanged()
            }
        )
    }
}
