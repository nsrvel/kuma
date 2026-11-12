import Foundation

struct KubeExecCredentials: Sendable {
    let kubeconfigPath: String?
    let context: String?
}

enum KubeConfigExecutionResolver {
    static func resolve(
        for provider: Provider,
        repo: any KubeConfigRepositoryProtocol = KubeConfigRepository(),
        userDefaults: UserDefaults = .standard
    ) async throws -> KubeExecCredentials {
        var normalized = provider
        if normalized.kubeConfigID == nil {
            normalized.kubeConfigID = KubeConfig.defaultID
        }

        let kubeconfigPath = try await KubeConfigMaterializer.kubectlKubeconfigPath(
            for: normalized,
            repo: repo,
            userDefaults: userDefaults
        )
        let yaml = try await loadYAML(
            for: normalized,
            kubeconfigPath: kubeconfigPath,
            repo: repo,
            userDefaults: userDefaults
        )
        let context = KubeConfigYAMLParser.resolveContextName(stored: provider.kubeContext, in: yaml)
        return KubeExecCredentials(kubeconfigPath: kubeconfigPath, context: context)
    }

    private static func loadYAML(
        for provider: Provider,
        kubeconfigPath: String?,
        repo: any KubeConfigRepositoryProtocol,
        userDefaults: UserDefaults
    ) async throws -> String {
        let configID = provider.kubeConfigID ?? KubeConfig.defaultID

        if configID == KubeConfig.defaultID {
            if let kubeconfigPath,
               let content = try? String(contentsOfFile: kubeconfigPath, encoding: .utf8) {
                return content
            }
            let customPath = KumaSettingsKey.string(
                forKey: KumaSettingsKey.customKubeconfigPath,
                fallbackKey: KumaSettingsKey.legacyKubeconfigPath,
                defaults: userDefaults
            )
            if let path = DependencyChecker.resolvedKubeconfigPath(customPath: customPath),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
            return ""
        }

        guard let record = try await repo.fetch(id: configID) else {
            throw ServiceExecutionError.invalidConfiguration("Selected kubeconfig no longer exists.")
        }
        return try CryptoVault.shared.decrypt(cipherText: record.configContent)
    }
}
