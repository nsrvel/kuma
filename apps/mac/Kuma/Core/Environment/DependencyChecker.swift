import Foundation
import Darwin

public struct DependencyStatus: Sendable, Equatable {
    public var kubectlInstalled: Bool
    public var kubeconfigExists: Bool
    public var dockerInstalled: Bool
    public var podmanInstalled: Bool
    public var cloudflaredInstalled: Bool
    public var ngrokInstalled: Bool

    public nonisolated init(
        kubectlInstalled: Bool = false,
        kubeconfigExists: Bool = false,
        dockerInstalled: Bool = false,
        podmanInstalled: Bool = false,
        cloudflaredInstalled: Bool = false,
        ngrokInstalled: Bool = false
    ) {
        self.kubectlInstalled = kubectlInstalled
        self.kubeconfigExists = kubeconfigExists
        self.dockerInstalled = dockerInstalled
        self.podmanInstalled = podmanInstalled
        self.cloudflaredInstalled = cloudflaredInstalled
        self.ngrokInstalled = ngrokInstalled
    }
}

public enum BinaryValidationResult: Equatable, Sendable {
    case empty
    case valid(path: String)
    case fileNotFound
    case notExecutable
    case nameMismatch(expected: String, actual: String)

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public var errorMessage: String? {
        switch self {
        case .empty, .valid:
            return nil
        case .fileNotFound:
            return "File does not exist at specified path"
        case .notExecutable:
            return "File is not an executable binary"
        case .nameMismatch(let expected, let actual):
            return "Selected file '\(actual)' does not match expected '\(expected)' binary"
        }
    }
}

public nonisolated enum DependencyChecker {
    private static let resolver = EnvironmentPathResolver.shared

    /// Synchronously validates a custom binary path without spawning subprocesses (zero-latency).
    public static func validateCustomBinary(path: String, expectedCommand: String) -> BinaryValidationResult {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let nsPath = NSString(string: trimmed).expandingTildeInPath
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: nsPath, isDirectory: &isDir) else {
            return .fileNotFound
        }

        guard !isDir.boolValue else {
            return .notExecutable
        }

        guard fm.isExecutableFile(atPath: nsPath) else {
            return .notExecutable
        }

        let fileName = (nsPath as NSString).lastPathComponent.lowercased()
        let expectedLower = expectedCommand.lowercased()

        // Permissive check: binary name must contain or start with command name
        if !fileName.contains(expectedLower) {
            return .nameMismatch(expected: expectedCommand, actual: (nsPath as NSString).lastPathComponent)
        }

        return .valid(path: nsPath)
    }

    /// Checks if a command binary is installed and executable.
    public static func isCommandInstalled(_ command: String, customPath: String? = nil) async -> Bool {
        return await resolvedPath(for: command, customPath: customPath) != nil
    }

    /// Resolves the absolute path for an executable binary.
    public static func resolvedPath(for command: String, customPath: String? = nil) async -> String? {
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nsPath = NSString(string: customPath).expandingTildeInPath
            let fm = FileManager.default
            if fm.fileExists(atPath: nsPath) && fm.isExecutableFile(atPath: nsPath) {
                return nsPath
            }
            return nil
        }
        return await resolver.resolveExecutablePath(for: command)
    }

    /// Real user home (`getpwuid`), not the app container home when they differ.
    public static func userHomePath() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    }

    /// Absolute path to `~/.kube/config` (file may or may not exist).
    public static func standardKubeconfigFilePath() -> String {
        (userHomePath() as NSString).appendingPathComponent(".kube/config")
    }

    /// Checks if ~/.kube/config or $KUBECONFIG exists.
    public static func isKubeconfigPresent(customPath: String? = nil) -> Bool {
        resolvedKubeconfigPath(customPath: customPath) != nil
    }

    /// Resolves the absolute path to the active kubeconfig file if it exists.
    public static func resolvedKubeconfigPath(customPath: String? = nil) -> String? {
        let fm = FileManager.default
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nsPath = NSString(string: customPath).expandingTildeInPath
            if fm.fileExists(atPath: nsPath) { return nsPath }
        }

        if let envKube = ProcessInfo.processInfo.environment["KUBECONFIG"], !envKube.isEmpty {
            let paths = envKube.split(separator: ":").map(String.init)
            for p in paths {
                let expanded = NSString(string: p).expandingTildeInPath
                if fm.fileExists(atPath: expanded) { return expanded }
            }
        }

        let defaultPath = standardKubeconfigFilePath()
        if fm.fileExists(atPath: defaultPath) {
            return defaultPath
        }

        return nil
    }


    /// Asynchronously runs scan on all core service engines & tunneling tools.
    public static func checkAll(
        customKubectlPath: String? = nil,
        customKubeconfigPath: String? = nil,
        customDockerPath: String? = nil,
        customPodmanPath: String? = nil,
        customCloudflaredPath: String? = nil,
        customNgrokPath: String? = nil
    ) async -> DependencyStatus {
        async let kubectl = isCommandInstalled("kubectl", customPath: customKubectlPath)
        async let docker = isCommandInstalled("docker", customPath: customDockerPath)
        async let podman = isCommandInstalled("podman", customPath: customPodmanPath)
        async let cloudflared = isCommandInstalled("cloudflared", customPath: customCloudflaredPath)
        async let ngrok = isCommandInstalled("ngrok", customPath: customNgrokPath)
        let kubeconfig = isKubeconfigPresent(customPath: customKubeconfigPath)

        return await DependencyStatus(
            kubectlInstalled: kubectl,
            kubeconfigExists: kubeconfig,
            dockerInstalled: docker,
            podmanInstalled: podman,
            cloudflaredInstalled: cloudflared,
            ngrokInstalled: ngrok
        )
    }
}
