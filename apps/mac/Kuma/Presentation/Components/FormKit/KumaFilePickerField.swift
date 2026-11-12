import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - KumaFilePickerField

public enum KumaFilePickerFieldStyle {
    /// Standalone field (Settings, SSH, etc.): body font, inset fill, hairline border.
    case standard
    /// Inside `KumaSourceField` file tab: smaller type, flat (no inner box).
    case embeddedInSourceField
}

public struct KumaFilePickerField: View {
    public let label: String
    @Binding public var path: String
    public var placeholder: String
    public var chooseFiles: Bool
    public var chooseDirectories: Bool
    public var allowedContentTypes: [UTType]?
    /// When true, NSOpenPanel still lists extensionless files (e.g. `~/.kube/config`).
    public var allowsOtherFileTypes: Bool
    /// Overrides initial folder for Browse; receives the current path binding value.
    public var browseDirectory: ((String) -> URL)?
    public var showsHiddenFiles: Bool
    public var error: String?
    public var style: KumaFilePickerFieldStyle

    @FocusState private var isFocused: Bool

    public init(
        label: String,
        path: Binding<String>,
        placeholder: String = "",
        chooseFiles: Bool = true,
        chooseDirectories: Bool = false,
        allowedContentTypes: [UTType]? = nil,
        allowsOtherFileTypes: Bool = false,
        browseDirectory: ((String) -> URL)? = nil,
        showsHiddenFiles: Bool = true,
        error: String? = nil,
        style: KumaFilePickerFieldStyle = .standard
    ) {
        self.label = label
        self._path = path
        self.placeholder = placeholder
        self.chooseFiles = chooseFiles
        self.chooseDirectories = chooseDirectories
        self.allowedContentTypes = allowedContentTypes
        self.allowsOtherFileTypes = allowsOtherFileTypes
        self.browseDirectory = browseDirectory
        self.showsHiddenFiles = showsHiddenFiles
        self.error = error
        self.style = style
    }

    private var pathFont: Font {
        switch style {
        case .standard: KumaFont.body
        case .embeddedInSourceField: KumaCodeEditorStyle.swiftUIFont
        }
    }

    private var pathPadding: CGFloat {
        switch style {
        case .standard: KumaSpacing.sm
        case .embeddedInSourceField: KumaCodeEditorStyle.textInset
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: KumaSpacing.sm) {
                ZStack(alignment: .leading) {
                    if path.isEmpty {
                        Text(placeholder)
                            .font(pathFont)
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $path)
                        .font(pathFont)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                }
                .padding(pathPadding)
                .modifier(KumaFilePickerPathChrome(style: style, isFocused: isFocused))

                Button("Browse") {
                    var config = KumaOpenPanel.Configuration()
                    config.chooseFiles = chooseFiles
                    config.chooseDirectories = chooseDirectories
                    config.showsHiddenFiles = showsHiddenFiles
                    config.allowedContentTypes = allowedContentTypes
                    config.allowsOtherFileTypes = allowsOtherFileTypes
                    config.browseDirectory = browseDirectory
                    config.placeholder = placeholder
                    if let picked = KumaOpenPanel.pickFile(currentPath: path, configuration: config) {
                        path = picked
                    }
                }

                .buttonStyle(.bordered)
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(KumaFont.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct KumaFilePickerPathChrome: ViewModifier {
    let style: KumaFilePickerFieldStyle
    let isFocused: Bool

    func body(content: Content) -> some View {
        switch style {
        case .standard:
            content
                .background(KumaColors.inputFieldFill, in: RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                        .stroke(
                            isFocused ? Color.accentColor : KumaColors.inputFieldStroke,
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
        case .embeddedInSourceField:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                        .stroke(
                            isFocused ? Color.accentColor : Color.clear,
                            lineWidth: isFocused ? 1.5 : 0
                        )
                )
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var path1 = "/usr/local/bin/docker"
        @State private var path2 = "/invalid/path/test"
        var body: some View {
            VStack(spacing: 16) {
                KumaFilePickerField(
                    label: "Docker Binary",
                    path: $path1,
                    placeholder: "/usr/local/bin/docker"
                )
                KumaFilePickerField(
                    label: "Custom Script Path",
                    path: $path2,
                    placeholder: "/path/to/script.sh",
                    error: "File does not exist at specified path"
                )
            }
            .padding()
            .frame(width: 500)
        }
    }
    return PreviewWrapper()
}
