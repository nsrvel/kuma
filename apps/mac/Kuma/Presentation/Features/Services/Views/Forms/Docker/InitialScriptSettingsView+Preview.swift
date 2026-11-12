import SwiftUI

#Preview {
    struct PreviewWrapper: View {
        @State private var script = ""
        @State private var path = ""

        var body: some View {
            KumaFormSection(icon: "terminal.fill", title: "Configuration") {
                InitialScriptSettingsView(initialScript: $script, initialScriptPath: $path)
            }
            .padding()
            .frame(width: 420)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
