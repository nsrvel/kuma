import SwiftUI

// MARK: - ShellScriptSettingsView

/// Configuration view for Shell Execution provider (Command + Working Directory).
public struct ShellScriptSettingsView: View {
    @Binding public var runCommand: String
    @Binding public var workingDirectory: String

    public init(runCommand: Binding<String>, workingDirectory: Binding<String>) {
        self._runCommand = runCommand
        self._workingDirectory = workingDirectory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KumaFilePickerField(
                label: "Working Directory",
                path: $workingDirectory,
                placeholder: "~/path/to/project",
                chooseFiles: false,
                chooseDirectories: true
            )

            KumaTextField(
                label: "Run Command",
                value: $runCommand,
                placeholder: "npm run dev"
            )
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var cmd = "npm run dev"
        @State private var dir = "~/Development/my-project"

        var body: some View {
            KumaFormSection(
                icon: "terminal.fill",
                title: "Shell Script"
            ) {
                ShellScriptSettingsView(runCommand: $cmd, workingDirectory: $dir)
            }
            .padding()
            .frame(width: 500)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
