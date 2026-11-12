import SwiftUI

public struct KubeConnectionSettingsView: View {
    @Binding public var kubeNamespace: String
    @Binding public var kubeContext: String
    public var availableContexts: [String]

    public init(
        kubeNamespace: Binding<String>,
        kubeContext: Binding<String>,
        availableContexts: [String] = []
    ) {
        self._kubeNamespace = kubeNamespace
        self._kubeContext = kubeContext
        self.availableContexts = availableContexts
    }

    private var contextOptions: [String] {
        availableContexts.isEmpty ? [""] : availableContexts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KumaRowPickerField(
                label: "Context",
                description: "Target Kubernetes context.",
                options: contextOptions,
                selection: $kubeContext,
                titleResolver: { opt in
                    if opt.isEmpty {
                        return availableContexts.isEmpty ? "No Contexts Available" : "Select Context"
                    }
                    return opt
                }
            )
            .disabled(availableContexts.isEmpty)


            Divider().opacity(0.3)

            KumaTextField(
                label: "Namespace",
                value: $kubeNamespace,
                placeholder: "staging"
            )
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var ns = "staging"
        @State private var ctx = "c1-ins-abc-stage"
        var body: some View {
            KumaFormSection(
                icon: "network",
                title: "Cluster Connection"
            ) {
                KubeConnectionSettingsView(
                    kubeNamespace: $ns,
                    kubeContext: $ctx,
                    availableContexts: ["c1-ins-abc-stage", "minikube", "docker-desktop"]
                )
            }
            .padding()
            .frame(width: 500)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
