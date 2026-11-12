import Foundation

public enum KumaFileMetadata {
    public static func fileSizeDescription(path: String) -> String? {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: expanded),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public static func truncatedParentPath(path: String, maxLength: Int = 40) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        let parent = (expanded as NSString).deletingLastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var display = parent
        if parent.hasPrefix(home) {
            display = "~" + String(parent.dropFirst(home.count))
        }
        if display.count <= maxLength { return display }
        return "…" + String(display.suffix(maxLength - 1))
    }
}
