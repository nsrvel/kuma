import SwiftUI

struct CreateServiceComposeConfigurationSection: View {
    let isPodman: Bool
    @Binding var yamlConfig: String
    @Binding var composeFilePath: String
    @Binding var initialScript: String
    @Binding var initialScriptPath: String

    var body: some View {
        KumaFormSection(icon: "shippingbox.fill", title: "Configuration") {
            VStack(alignment: .leading, spacing: KumaSpacing.md) {
                if isPodman {
                    PodmanComposeSettingsView(yamlConfig: $yamlConfig, composeFilePath: $composeFilePath)
                } else {
                    DockerComposeSettingsView(yamlConfig: $yamlConfig, composeFilePath: $composeFilePath)
                }
                InitialScriptSettingsView(
                    initialScript: $initialScript,
                    initialScriptPath: $initialScriptPath
                )
            }
        }
    }
}

#Preview {
    struct Wrapper: View {
        @State private var yaml = ""
        @State private var composePath = ""
        @State private var script = ""
        @State private var scriptPath = ""
        var body: some View {
            CreateServiceComposeConfigurationSection(
                isPodman: false,
                yamlConfig: $yaml,
                composeFilePath: $composePath,
                initialScript: $script,
                initialScriptPath: $scriptPath
            )
            .padding()
            .frame(width: 420)
        }
    }
    return Wrapper()
}
