import Foundation
import os

/// Thread-safe actor responsible for sniffing user login shell `$PATH`
/// and locating executable binary paths across standard macOS locations.
public actor EnvironmentPathResolver {
    /// Shared singleton instance for application-wide path resolution.
    public static let shared = EnvironmentPathResolver()

    private let logger = Logger(subsystem: "lokastudio.kuma", category: "EnvironmentPathResolver")
    private var cachedPath: String?
    private var customPaths: [String] = []

    /// Default fallback paths on macOS if shell PATH resolution is incomplete or empty.
    private static let fallbackDirectories: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "\(NSHomeDirectory())/.rd/bin",
        "\(NSHomeDirectory())/.nvm/versions/node/current/bin",
        "\(NSHomeDirectory())/.cargo/bin",
        "\(NSHomeDirectory())/.local/bin"
    ]

    public init() {}

    // MARK: - Public API

    /// Returns the resolved system `$PATH` string separated by colons (`:`).
    /// Uses cached result if available, otherwise sniffs via non-interactive login shell.
    public func resolvePath() async -> String {
        if let cached = cachedPath {
            return cached
        }

        let sniffed = sniffShellPath()
        let combined = combinePaths(sniffed: sniffed)
        self.cachedPath = combined
        logger.debug("Resolved system PATH: \(combined, privacy: .public)")
        return combined
    }

    /// Resolves the full absolute file path for a given binary name or raw path (e.g. "kubectl", "docker").
    /// Returns `nil` if binary cannot be found or is not executable.
    public func resolveExecutablePath(for binaryOrPath: String) async -> String? {
        let trimmed = binaryOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fileManager = FileManager.default

        // 1. If it's already an absolute path, check directly
        if trimmed.hasPrefix("/") {
            if isExecutableFile(atPath: trimmed, fileManager: fileManager) {
                return trimmed
            }
            return nil
        }

        // 2. Expand tilde paths (e.g. "~/bin/mytool")
        if trimmed.hasPrefix("~") {
            let nsPath = NSString(string: trimmed).expandingTildeInPath
            if isExecutableFile(atPath: nsPath, fileManager: fileManager) {
                return nsPath
            }
            return nil
        }

        // 3. Search through resolved PATH components
        let systemPath = await resolvePath()
        let pathComponents = systemPath.split(separator: ":").map(String.init)

        for dir in pathComponents {
            let expandedDir = (dir as NSString).expandingTildeInPath
            let candidatePath = (expandedDir as NSString).appendingPathComponent(trimmed)
            if isExecutableFile(atPath: candidatePath, fileManager: fileManager) {
                return candidatePath
            }
        }

        logger.warning("Failed to locate executable for binary: \(trimmed, privacy: .public)")
        return nil
    }

    /// Invalidates the cached PATH and re-evaluates the environment shell `$PATH`.
    @discardableResult
    public func refreshPath() async -> String {
        self.cachedPath = nil
        return await resolvePath()
    }

    /// Sets custom user paths to take high precedence during binary resolution.
    public func setCustomPaths(_ paths: [String]) {
        self.customPaths = paths
        self.cachedPath = nil
    }

    // MARK: - Private Helpers

    /// Sniffs `$PATH` by invoking user's default login shell (`$SHELL`), falling back to `/bin/zsh`.
    private func sniffShellPath() -> String {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let executableURL: URL

        if FileManager.default.isExecutableFile(atPath: shellPath) {
            executableURL = URL(fileURLWithPath: shellPath)
        } else {
            executableURL = URL(fileURLWithPath: "/bin/zsh")
        }

        let isFish = executableURL.lastPathComponent == "fish"
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        if isFish {
            process.arguments = ["-c", "echo $PATH"]
        } else {
            let bootstrap = "[ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; echo $PATH"
            process.arguments = ["-c", bootstrap]
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        defer {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let formatted = isFish ? trimmed.replacingOccurrences(of: " ", with: ":") : trimmed
                    return formatted
                }
            }
        } catch {
            logger.error("Failed to sniff login shell PATH: \(error.localizedDescription, privacy: .public)")
        }

        return ProcessInfo.processInfo.environment["PATH"] ?? ""
    }

    private func combinePaths(sniffed: String) -> String {
        var seen = Set<String>()
        var orderedDirectories: [String] = []

        let appendIfNew: (String) -> Void = { dir in
            let cleaned = dir.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { return }
            seen.insert(cleaned)
            orderedDirectories.append(cleaned)
        }

        for dir in customPaths { appendIfNew(dir) }
        let sniffedComponents = sniffed.split(separator: ":").map(String.init)
        for dir in sniffedComponents { appendIfNew(dir) }
        for dir in Self.discoverNodeAndToolDirectories() { appendIfNew(dir) }
        for dir in Self.fallbackDirectories { appendIfNew(dir) }

        return orderedDirectories.joined(separator: ":")
    }

    private static func discoverNodeAndToolDirectories() -> [String] {
        var results: [String] = []
        let home = NSHomeDirectory()

        // 1. Dynamically scan all installed NVM node versions
        let nvmVersions = URL(fileURLWithPath: "\(home)/.nvm/versions/node")
        if let dirs = try? FileManager.default.contentsOfDirectory(at: nvmVersions, includingPropertiesForKeys: nil) {
            for dir in dirs {
                results.append(dir.appendingPathComponent("bin").path(percentEncoded: false))
            }
        }

        // 2. Additional developer tool paths
        results.append("\(home)/Library/pnpm")
        results.append("\(home)/.bun/bin")
        results.append("\(home)/go/bin")

        return results
    }

    private func isExecutableFile(atPath path: String, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: path)
    }
}
