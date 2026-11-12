import AppKit
import UniformTypeIdentifiers

public enum KumaOpenPanel {
    public struct Configuration {
        public var chooseFiles: Bool = true
        public var chooseDirectories: Bool = false
        public var allowedContentTypes: [UTType]?
        public var allowsOtherFileTypes: Bool = false
        public var showsHiddenFiles: Bool = true
        public var browseDirectory: ((String) -> URL)?
        public var pathHint: String = ""
        public var placeholder: String = ""

        public init() {}
    }

    @discardableResult
    @MainActor
    public static func pickFile(
        currentPath: String = "",
        configuration: Configuration = Configuration()
    ) -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = configuration.chooseFiles
        panel.canChooseDirectories = configuration.chooseDirectories
        panel.showsHiddenFiles = configuration.showsHiddenFiles
        panel.resolvesAliases = true

        if let allowedContentTypes = configuration.allowedContentTypes {
            panel.allowedContentTypes = allowedContentTypes
        }
        panel.allowsOtherFileTypes = configuration.allowsOtherFileTypes

        if let browseDirectory = configuration.browseDirectory {
            panel.directoryURL = browseDirectory(currentPath)
        } else {
            panel.directoryURL = defaultBrowseDirectory(
                path: currentPath,
                placeholder: configuration.placeholder.isEmpty ? configuration.pathHint : configuration.placeholder
            )
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }

    public static func defaultBrowseDirectory(path: String, placeholder: String) -> URL {
        let fm = FileManager.default
        let targetPath = path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : path
        if !targetPath.isEmpty {
            let expanded = NSString(string: targetPath).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
            let dirPath = (expanded as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: dirPath) {
                return URL(fileURLWithPath: dirPath, isDirectory: true)
            }
        }
        return fm.homeDirectoryForCurrentUser
    }
}
