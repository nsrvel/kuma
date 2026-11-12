import Foundation
import CryptoKit
import os

// MARK: - Validation Result & Cache

public struct KubeValidationResult: Sendable, Equatable {
    public let isReachable: Bool
    public let errorMessage: String?
    public let verifiedAt: Date

    public nonisolated init(isReachable: Bool, errorMessage: String? = nil, verifiedAt: Date = Date()) {
        self.isReachable = isReachable
        self.errorMessage = errorMessage
        self.verifiedAt = verifiedAt
    }
}

// MARK: - KubeConnectionValidator (Background Actor)

/// High-performance background actor that tests Kubernetes connectivity with smart in-memory caching.
/// All subprocesses run fully off the main thread with zero UI latency and automatic task cancellation.
public actor KubeConnectionValidator {
    public static let shared = KubeConnectionValidator()

    private let logger = Logger(subsystem: "lokastudio.kuma", category: "KubeConnectionValidator")
    private var validationCache: [String: KubeValidationResult] = [:]

    public init() {}

    /// Computes the unique cache key based on the SHA-256 hash of (config content + target context).
    private func computeCacheKey(content: String, context: String) -> String {
        let combined = "\(content)::\(context)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Verifies connectivity to the cluster. Returns cached result immediately if present unless `forceRefresh` is true.
    public func validateConnection(
        configContent: String,
        context: String,
        forceRefresh: Bool = false
    ) async -> KubeValidationResult {
        let trimmedContent = configContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return KubeValidationResult(isReachable: false, errorMessage: "Empty kubeconfig content")
        }

        let cacheKey = computeCacheKey(content: trimmedContent, context: context)

        // 1. Check cache if not forcing refresh
        if !forceRefresh, let cached = validationCache[cacheKey] {
            logger.debug("Returning cached Kubernetes validation result (reachable: \(cached.isReachable))")
            return cached
        }

        // 2. Resolve kubectl binary path
        guard let kubectlPath = await KumaSettingsExecutableResolver.kubectl() else {
            let errorResult = KubeValidationResult(isReachable: false, errorMessage: "kubectl binary not found in system PATH")
            validationCache[cacheKey] = errorResult
            return errorResult
        }

        // 3. Write temp config file and run non-blocking validation
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("kuma-chk-\(UUID().uuidString).yaml")

        do {
            try trimmedContent.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }

            // Check for Task cancellation before spawning subprocess
            try Task.checkCancellation()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: kubectlPath)
            var args = ["--kubeconfig", tempFile.path, "version", "--output=yaml", "--request-timeout=4s"]
            let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContext.isEmpty {
                args.append(contentsOf: ["--context", trimmedContext])
            }
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            defer {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }

            try process.run()

            // Non-blocking exit wait with cancellation safety
            await withTaskCancellationHandler {
                process.waitUntilExit()
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(data: outputData, encoding: .utf8) ?? ""

            // Success if exit code is 0 and output contains serverVersion
            let isReachable = (process.terminationStatus == 0) && (outputText.contains("serverVersion") || outputText.contains("gitVersion"))
            let result: KubeValidationResult
            if isReachable {
                result = KubeValidationResult(isReachable: true, errorMessage: nil)
            } else {
                result = KubeValidationResult(isReachable: false, errorMessage: "Unable to reach cluster")
            }

            self.validationCache[cacheKey] = result
            return result
        } catch is CancellationError {
            logger.debug("Kubernetes validation task was cancelled.")
            return KubeValidationResult(isReachable: false, errorMessage: "Validation cancelled")
        } catch {
            let result = KubeValidationResult(isReachable: false, errorMessage: error.localizedDescription)
            self.validationCache[cacheKey] = result
            return result
        }
    }

    /// Clears the memory cache (e.g. on workspace switch or network change).
    public func clearCache() {
        validationCache.removeAll()
    }
}
