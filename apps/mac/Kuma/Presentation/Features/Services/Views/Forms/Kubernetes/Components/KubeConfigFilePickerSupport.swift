import Foundation
import UniformTypeIdentifiers

enum KubeConfigFilePickerSupport {
    static let defaultConfigPlaceholder = "~/.kube/config"

    /// YAML extensions plus plain text; extensionless `config` is allowed via `allowsOtherFileTypes`.
    static let allowedContentTypes: [UTType] = ComposeFileTypes.allowed

    /// Initial Browse folder: existing file's directory, else `~/.kube` / detected kubeconfig, else home.
    static func browseDirectoryURL(for currentPath: String) -> URL {
        let fm = FileManager.default
        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir) {
                if isDir.boolValue {
                    return URL(fileURLWithPath: expanded, isDirectory: true)
                }
                let parent = (expanded as NSString).deletingLastPathComponent
                if fm.fileExists(atPath: parent) {
                    return URL(fileURLWithPath: parent, isDirectory: true)
                }
            } else {
                let parent = (expanded as NSString).deletingLastPathComponent
                if fm.fileExists(atPath: parent) {
                    return URL(fileURLWithPath: parent, isDirectory: true)
                }
            }
        }

        if let resolved = DependencyChecker.resolvedKubeconfigPath() {
            let parent = (resolved as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: parent) {
                return URL(fileURLWithPath: parent, isDirectory: true)
            }
        }

        let defaultExpanded = NSString(string: defaultConfigPlaceholder).expandingTildeInPath
        let kubeDir = (defaultExpanded as NSString).deletingLastPathComponent
        if fm.fileExists(atPath: kubeDir) {
            return URL(fileURLWithPath: kubeDir, isDirectory: true)
        }

        return fm.homeDirectoryForCurrentUser
    }
}
