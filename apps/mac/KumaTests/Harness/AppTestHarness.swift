import Foundation
@testable import Kuma

/// Isolated test sandbox for Feature 00 (App Foundation).
/// Provides temporary directories for Application Support, Library/Sounds, and custom files
/// with 100% deterministic cleanup upon deallocation.
@MainActor
public final class AppTestHarness {
    private var tempDirectories: [String] = []
    private var tempFiles: [String] = []
    private let fileManager = FileManager.default

    public init() {}

    deinit {
        // Safe cleanup invoked upon deallocation
        for file in tempFiles {
            try? FileManager.default.removeItem(atPath: file)
        }
        for dir in tempDirectories {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    public func cleanup() {
        for file in tempFiles {
            try? fileManager.removeItem(atPath: file)
        }
        tempFiles.removeAll()

        for dir in tempDirectories {
            try? fileManager.removeItem(atPath: dir)
        }
        tempDirectories.removeAll()
    }

    /// Creates an isolated temporary directory.
    @discardableResult
    public func createTempDirectory(prefix: String = "kuma_fnd_test") -> String {
        let tempDir = NSTemporaryDirectory()
        let dirPath = (tempDir as NSString).appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try? fileManager.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        tempDirectories.append(dirPath)
        return dirPath
    }

    /// Creates an isolated temporary file with custom attributes.
    @discardableResult
    public func createTempFile(
        inDirectory dir: String? = nil,
        named name: String,
        content: Data = Data(),
        permissions: Int? = nil
    ) -> String {
        let parentDir = dir ?? createTempDirectory()
        let filePath = (parentDir as NSString).appendingPathComponent(name)

        var attributes: [FileAttributeKey: Any]? = nil
        if let permissions {
            attributes = [.posixPermissions: permissions]
        }

        fileManager.createFile(atPath: filePath, contents: content, attributes: attributes)
        tempFiles.append(filePath)
        return filePath
    }
}
