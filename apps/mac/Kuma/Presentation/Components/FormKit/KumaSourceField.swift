import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Mode

public enum KumaDualSourceMode: String, CaseIterable, Identifiable, Hashable {
    case chooseFile
    case pasteYAML

    public var id: String { rawValue }

    public nonisolated static func inferred(path: String, text: String, fallback: KumaDualSourceMode) -> KumaDualSourceMode {
        if !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .chooseFile }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .pasteYAML }
        return fallback
    }
}

// MARK: - Field

public struct KumaSourceField: View {
    public let label: String
    @Binding public var mode: KumaDualSourceMode
    @Binding public var path: String
    @Binding public var text: String

    public var fileTabLabel: String
    public var pasteTabLabel: String
    public var filePrompt: String
    public var editorPlaceholder: String
    public var editorMinHeight: CGFloat
    public var editorMaxHeight: CGFloat?
    public var allowedContentTypes: [UTType]?
    public var allowsOtherFileTypes: Bool
    public var browseDirectory: ((String) -> URL)?
    public var showsHiddenFiles: Bool
    public var isLocked: Bool

    @State private var editorFocused: Bool = false
    @State private var allowsPasteEditorFocus: Bool = false

    public init(
        label: String,
        mode: Binding<KumaDualSourceMode>,
        path: Binding<String>,
        text: Binding<String>,
        fileTabLabel: String = "File",
        pasteTabLabel: String = "Paste YAML",
        filePrompt: String = "Choose a file…",
        editorPlaceholder: String = "",
        editorMinHeight: CGFloat = 160,
        editorMaxHeight: CGFloat? = nil,
        allowedContentTypes: [UTType]? = nil,
        allowsOtherFileTypes: Bool = false,
        browseDirectory: ((String) -> URL)? = nil,
        showsHiddenFiles: Bool = true,
        isLocked: Bool = false
    ) {
        self.label = label
        self._mode = mode
        self._path = path
        self._text = text
        self.fileTabLabel = fileTabLabel
        self.pasteTabLabel = pasteTabLabel
        self.filePrompt = filePrompt
        self.editorPlaceholder = editorPlaceholder
        self.editorMinHeight = editorMinHeight
        self.editorMaxHeight = editorMaxHeight
        self.allowedContentTypes = allowedContentTypes
        self.allowsOtherFileTypes = allowsOtherFileTypes
        self.browseDirectory = browseDirectory
        self.showsHiddenFiles = showsHiddenFiles
        self.isLocked = isLocked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KumaSpacing.xs) {
            if !label.isEmpty {
                Text(label)
                    .font(KumaFont.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                modeStrip
                Rectangle()
                    .fill(KumaColors.inputFieldStroke)
                    .frame(height: 0.5)
                modeContent
            }
            .background(KumaColors.inputFieldFill, in: RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KumaRadius.sm, style: .continuous)
                    .strokeBorder(KumaColors.inputFieldStroke, lineWidth: 0.5)
            )
        }
    }

    private func prepareFocusForModeChange() {
        editorFocused = false
        allowsPasteEditorFocus = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: 0) {
            modeTab(.chooseFile, icon: "doc", title: fileTabLabel)
            modeTab(.pasteYAML, icon: "text.alignleft", title: pasteTabLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, KumaSpacing.sm)
        .padding(.top, KumaSpacing.sm)
        .padding(.bottom, KumaSpacing.xs)
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private func modeTab(_ option: KumaDualSourceMode, icon: String, title: String) -> some View {
        KumaInspectorSegmentButton(
            systemImage: icon,
            title: title,
            isSelected: mode == option,
            isDisabled: isLocked,
            accessibilityLabel: title,
            action: {
                guard mode != option else { return }
                prepareFocusForModeChange()
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = option
                }
            }
        )
    }

    @ViewBuilder
    private var modeContent: some View {
        Group {
            if mode == .chooseFile {
                fileContent
            } else {
                pasteContent
            }
        }
        .padding(KumaSpacing.sm)
    }

    private var fileContent: some View {
        KumaFilePickerField(
            label: "",
            path: $path,
            placeholder: filePrompt,
            chooseFiles: true,
            chooseDirectories: false,
            allowedContentTypes: allowedContentTypes,
            allowsOtherFileTypes: allowsOtherFileTypes,
            browseDirectory: browseDirectory,
            showsHiddenFiles: showsHiddenFiles,
            style: .embeddedInSourceField
        )
        .disabled(isLocked)
        .kumaAcceptFileDrop(isEnabled: !isLocked) { url in
            path = url.path(percentEncoded: false)
        }
    }

    private var pasteContent: some View {
        KumaCodeEditor(
            code: $text,
            placeholder: editorPlaceholder,
            minHeight: editorMinHeight,
            maxHeight: editorMaxHeight,
            isReadOnly: isLocked,
            showsChrome: false,
            isFocused: $editorFocused,
            allowsKeyboardFocus: $allowsPasteEditorFocus
        )
    }

}

private extension View {
    @ViewBuilder
    func kumaAcceptFileDrop(isEnabled: Bool, onPick: @MainActor @escaping (URL) -> Void) -> some View {
        if #available(macOS 26.0, *) {
            dropDestination(for: URL.self) { urls, _ in
                guard isEnabled, let url = urls.first else { return false }
                onPick(url)
                return true
            }
        } else {
            onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard isEnabled, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    guard let url = object else { return }
                    Task { @MainActor in onPick(url) }
                }
                return true
            }
        }
    }
}

#Preview("KumaSourceField") {
    struct Wrapper: View {
        @State private var mode = KumaDualSourceMode.chooseFile
        @State private var path = ""
        @State private var text = "services:\n  web:\n    image: nginx"

        var body: some View {
            VStack(spacing: KumaSpacing.lg) {
                KumaSourceField(
                    label: "Compose File",
                    mode: $mode,
                    path: $path,
                    text: $text,
                    filePrompt: "Choose docker-compose.yml…",
                    editorPlaceholder: "version: '3.8'\nservices:"
                )

                KumaSourceField(
                    label: "Locked",
                    mode: .constant(.pasteYAML),
                    path: .constant(""),
                    text: .constant("readonly"),
                    isLocked: true
                )
            }
            .padding()
            .frame(width: 420)
            .background(KumaColors.canvasBackground)
        }
    }
    return Wrapper()
}
