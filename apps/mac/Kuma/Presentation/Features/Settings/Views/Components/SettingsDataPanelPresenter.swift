import AppKit
import UniformTypeIdentifiers

@MainActor
public enum SettingsDataPanelPresenter {
    public static func presentSavePanel(
        title: String,
        defaultFileName: String,
        allowedTypes: [UTType] = [.json],
        onSelect: @escaping (URL) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = allowedTypes

        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    onSelect(url)
                }
            }
            return
        }

        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                onSelect(url)
            }
        }
    }

    public static func presentOpenPanel(
        title: String,
        allowedTypes: [UTType] = [.json],
        onSelect: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedTypes

        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    onSelect(url)
                }
            }
            return
        }

        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                onSelect(url)
            }
        }
    }
}
