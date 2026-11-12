import Foundation
import os

/// Isolated test harness for Feature 02: Settings & Preferences.
/// Handles isolated UserDefaults suites, temp mock executables, mock YAML files, and tear down.
/// Isolated to `@MainActor` for 100% Swift 6 Strict Concurrency compliance without `@unchecked Sendable`.
@MainActor
public final class SettingsTestHarness {
    public let suiteName: String
    public let userDefaults: UserDefaults
    private var createdFilePaths: [String] = []
    private let fileManager = FileManager.default

    public init(suiteName: String = "kuma.tests.settings.\(UUID().uuidString)") {
        self.suiteName = suiteName
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.userDefaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        for path in createdFilePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    public func cleanup() {
        userDefaults.removePersistentDomain(forName: suiteName)
        for path in createdFilePaths {
            try? fileManager.removeItem(atPath: path)
        }
        createdFilePaths.removeAll()
    }

    /// Creates a dummy executable file with POSIX permissions 0755 (`chmod +x`).
    @discardableResult
    public func createExecutable(named name: String, content: String = "#!/bin/sh\necho ok") -> String {
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

    /// Creates a dummy kubeconfig file.
    @discardableResult
    public func createKubeconfigFile(content: String = "apiVersion: v1\nkind: Config\nclusters: []") -> String {
        let tempDir = NSTemporaryDirectory()
        let filePath = (tempDir as NSString).appendingPathComponent("\(UUID().uuidString)_kubeconfig.yaml")
        fileManager.createFile(atPath: filePath, contents: content.data(using: .utf8))
        createdFilePaths.append(filePath)
        return filePath
    }
}
