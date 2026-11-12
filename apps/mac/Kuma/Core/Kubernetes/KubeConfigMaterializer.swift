import Foundation

/// Resolves a provider's kubeconfig selection to a filesystem path for `kubectl --kubeconfig`.
enum KubeConfigMaterializer {
    static func kubectlKubeconfigPath(
        for provider: Provider,
        repo: any KubeConfigRepositoryProtocol = KubeConfigRepository(),
        userDefaults: UserDefaults = .standard
    ) async throws -> String? {
        // ponytail: customKubeConfigPath is legacy import-only; UI writes kubeConfigID instead.
        if let legacy = provider.customKubeConfigPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            let expanded = NSString(string: legacy).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }

        let configID = provider.kubeConfigID ?? KubeConfig.defaultID

        if configID == KubeConfig.defaultID {
            let customPath = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customKubeconfigPath,
                fallbackKey: KumaSettingsKey.legacyKubeconfigPath,
                defaults: userDefaults
            )
            return DependencyChecker.resolvedKubeconfigPath(customPath: customPath)
        }

        guard let record = try await repo.fetch(id: configID) else {
            throw ServiceExecutionError.invalidConfiguration("Selected kubeconfig no longer exists.")
        }

        if let rawPath = record.sourceFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
            throw ServiceExecutionError.invalidConfiguration("Kubeconfig file not found at \(rawPath).")
        }

        let plain = try CryptoVault.shared.decrypt(cipherText: record.configContent)
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("Selected kubeconfig is empty.")
        }

        let fileURL = try materializedFileURL(for: configID)
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        return fileURL.path(percentEncoded: false)
    }

    private static func materializedFileURL(for configID: UUID) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Kuma/kubeconfigs", isDirectory: true)

        if !fm.fileExists(atPath: base.path(percentEncoded: false)) {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            try fm.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: base.path(percentEncoded: false)
            )
        }

        return base.appendingPathComponent("\(configID.uuidString).yaml")
    }
}
