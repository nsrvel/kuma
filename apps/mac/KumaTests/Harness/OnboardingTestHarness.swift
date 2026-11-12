import Foundation

/// Lean test harness for Onboarding file system mocks and clean teardown.
/// Isolated to `@MainActor` for 100% Swift 6 Strict Concurrency safety without `@unchecked Sendable`.
@MainActor
public final class OnboardingTestHarness {
    public let suiteName: String
    public let userDefaults: UserDefaults
    private var createdFilePaths: [String] = []
    private let fileManager = FileManager.default

    public init(suiteName: String = "kuma.tests.onboarding.\(UUID().uuidString)") {
        self.suiteName = suiteName
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.userDefaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        // Safe cleanup invoked upon deallocation
        for path in createdFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Creates an executable file in user's home directory (e.g. for testing tilde expansion) and tracks for automatic cleanup.
    @discardableResult
    public func createHomeExecutable(named name: String, content: String = "#!/bin/sh\necho ok") -> (realPath: String, tildePath: String) {
        let homeDir = fileManager.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let uniqueName = "\(UUID().uuidString)_\(name)"
        let realPath = (homeDir as NSString).appendingPathComponent(uniqueName)

        fileManager.createFile(atPath: realPath, contents: content.data(using: .utf8), attributes: [
            .posixPermissions: 0o755
        ])
        createdFilePaths.append(realPath)
        return (realPath, "~/\(uniqueName)")
    }

    /// Creates a temporary dummy executable file with POSIX permissions 0755 (`chmod +x`).
    @discardableResult
    public func createDummyExecutable(named name: String, content: String = "#!/bin/sh\necho ok") -> String {
        let tempDir = NSTemporaryDirectory()
        let uniqueName = "\(UUID().uuidString)_\(name)"
        let filePath = (tempDir as NSString).appendingPathComponent(uniqueName)

        fileManager.createFile(atPath: filePath, contents: content.data(using: .utf8), attributes: [
            .posixPermissions: 0o755
        ])
        createdFilePaths.append(filePath)
        return filePath
    }

    /// Creates a regular non-executable file with POSIX permissions 0644 (`chmod -x`).
    @discardableResult
    public func createNonExecutableFile(named name: String, content: String = "plain text") -> String {
        let tempDir = NSTemporaryDirectory()
        let uniqueName = "\(UUID().uuidString)_\(name)"
        let filePath = (tempDir as NSString).appendingPathComponent(uniqueName)

        fileManager.createFile(atPath: filePath, contents: content.data(using: .utf8), attributes: [
            .posixPermissions: 0o644
        ])
        createdFilePaths.append(filePath)
        return filePath
    }

    /// Creates a temporary directory.
    @discardableResult
    public func createTempDirectory(named name: String) -> String {
        let tempDir = NSTemporaryDirectory()
        let dirPath = (tempDir as NSString).appendingPathComponent("\(UUID().uuidString)_\(name)")
        try? fileManager.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        createdFilePaths.append(dirPath)
        return dirPath
    }

    /// Creates a dummy kubeconfig YAML text file.
    @discardableResult
    public func createDummyKubeconfig(content: String = "apiVersion: v1\nkind: Config\nclusters: []") -> String {
        let tempDir = NSTemporaryDirectory()
        let filePath = (tempDir as NSString).appendingPathComponent("\(UUID().uuidString)_config.yaml")
        fileManager.createFile(atPath: filePath, contents: content.data(using: .utf8))
        createdFilePaths.append(filePath)
        return filePath
    }

    /// Creates a symbolic link pointing to a destination path.
    @discardableResult
    public func createSymlink(named name: String, pointingTo targetPath: String) -> String {
        let tempDir = NSTemporaryDirectory()
        let linkPath = (tempDir as NSString).appendingPathComponent("\(UUID().uuidString)_\(name)")
        try? fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: targetPath)
        createdFilePaths.append(linkPath)
        return linkPath
    }

    /// Creates a broken symbolic link whose target file does not exist.
    @discardableResult
    public func createBrokenSymlink(named name: String) -> String {
        let nonExistentTarget = (NSTemporaryDirectory() as NSString).appendingPathComponent("deleted_\(UUID().uuidString)")
        return createSymlink(named: name, pointingTo: nonExistentTarget)
    }

    /// Cleans up all temporary files and directories created during the test run and purges isolated userDefaults.
    public func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
        for path in createdFilePaths {
            try? fileManager.removeItem(atPath: path)
        }
        createdFilePaths.removeAll()
    }
}
