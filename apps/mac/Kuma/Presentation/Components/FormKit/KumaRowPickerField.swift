import SwiftUI

// MARK: - KumaRowPickerField

public struct KumaRowPickerField<Option: Hashable>: View {
    public let label: String
    public var description: String?
    public let options: [Option]
    @Binding public var selection: Option
    public let titleResolver: (Option) -> String

    public init(
        label: String,
        description: String? = nil,
        options: [Option],
        selection: Binding<Option>,
        titleResolver: @escaping (Option) -> String
    ) {
        self.label = label
        self.description = description
        self.options = options
        self._selection = selection
        self.titleResolver = titleResolver
    }

    public var body: some View {
        HStack(alignment: .center, spacing: KumaSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(KumaFont.body)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(KumaFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: KumaSpacing.md)

            Picker("", selection: $selection) {
                if !options.contains(selection) {
                    Text(titleResolver(selection)).tag(selection)
                }
                ForEach(options, id: \.self) { opt in
                    Text(titleResolver(opt)).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var shell = "/bin/zsh"
        var body: some View {
            KumaRowPickerField(
                label: "Default Shell",
                description: "The shell to use when executing commands.",
                options: ["/bin/zsh", "/bin/bash", "/opt/homebrew/bin/fish"],
                selection: $shell,
                titleResolver: { $0.contains("zsh") ? "Zsh" : ($0.contains("bash") ? "Bash" : "Fish") }
            )
            .padding()
            .frame(width: 450)
        }
    }
    return PreviewWrapper()
}
