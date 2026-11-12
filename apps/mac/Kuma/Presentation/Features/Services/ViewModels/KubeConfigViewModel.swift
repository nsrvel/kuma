import Foundation
import Observation
import SwiftUI
import os

// MARK: - KubeConfigViewModel

@Observable
@MainActor
public final class KubeConfigViewModel {
    private nonisolated static let logger = Logger(subsystem: "lokastudio.kuma", category: "KubeConfigViewModel")

    public var availableKubeConfigs: [KubeConfig] = []
    public var selectedKubeConfigID: UUID? = nil {
        didSet {
            if oldValue != selectedKubeConfigID {
                reloadDefaultKubeConfigContentIfNeeded()
                refreshContextsForCurrentConfig()
                triggerBackgroundValidation()
            }
        }
    }

    /// Extracted context names from the currently selected kubeconfig
    public var availableContexts: [String] = []
    /// The active context defined by `current-context:` in the yaml
    public var activeContextName: String? = nil

    // Form inline states
    public var showInlineNewConfigForm: Bool = false
    public var editingKubeConfigID: UUID? = nil
    public var showDeleteConfirmation: Bool = false
    public var newKubeConfigName: String = ""
    public var newKubeConfigContent: String = ""
    public var newKubeConfigSourcePath: String = ""

    // Connection testing states
    public var connectionError: String? = nil
    public var isLoadingNamespaces: Bool = false
    public var connectionSuccess: Bool = false

    private let repo: any KubeConfigRepositoryProtocol
    private var activeValidationTask: Task<Void, Never>? = nil
    private let userDefaults: UserDefaults

    public init(
        repo: any KubeConfigRepositoryProtocol = KubeConfigRepository(),
        userDefaults: UserDefaults = .standard
    ) {
        self.repo = repo
        self.userDefaults = userDefaults
    }

    public func loadConfigs(preferredSelectionID: UUID? = nil) async {
        let repo = self.repo
        let customPath = KumaSettingsKey.string(
            forKey: KumaSettingsKey.customKubeconfigPath,
            fallbackKey: KumaSettingsKey.legacyKubeconfigPath,
            defaults: self.userDefaults
        )
        let finalizedList = await Task.detached(priority: .utility) { () -> [KubeConfig] in
            return await Self.fetchAndDecryptConfigs(repo: repo, customPath: customPath)
        }.value

        self.availableKubeConfigs = finalizedList
        if let preferredSelectionID,
           finalizedList.contains(where: { $0.id == preferredSelectionID }) {
            self.selectedKubeConfigID = preferredSelectionID
        } else if let current = selectedKubeConfigID,
                  finalizedList.contains(where: { $0.id == current }) {
            // Keep current selection when still valid.
        } else if let first = finalizedList.first {
            self.selectedKubeConfigID = first.id
        }
        self.refreshContextsForCurrentConfig()
    }

    private nonisolated static func fetchAndDecryptConfigs(
        repo: any KubeConfigRepositoryProtocol,
        customPath: String?
    ) async -> [KubeConfig] {
        var list: [KubeConfig] = []

        let defaultPath = DependencyChecker.resolvedKubeconfigPath(customPath: customPath)
            ?? {
                let standard = DependencyChecker.standardKubeconfigFilePath()
                return FileManager.default.fileExists(atPath: standard) ? standard : nil
            }()
        let defaultFilePath = defaultPath ?? DependencyChecker.standardKubeconfigFilePath()
        let defaultContent: String
        if let defaultPath {
            defaultContent = (try? String(contentsOfFile: defaultPath, encoding: .utf8)) ?? ""
        } else {
            defaultContent = ""
        }
        list.append(
            KubeConfig(
                id: KubeConfig.defaultID,
                name: "Default",
                configContent: defaultContent,
                sourceFilePath: defaultFilePath,
                isDefault: true
            )
        )

        // Fetch custom registered configs from DB and decrypt contents
        do {
            let customConfigs = try await repo.fetchAll()
            var decryptedList: [KubeConfig] = []
            for config in customConfigs where config.id != KubeConfig.defaultID {
                var decrypted = config
                if let path = config.sourceFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    let expanded = NSString(string: path).expandingTildeInPath
                    decrypted.configContent = (try? String(contentsOfFile: expanded, encoding: .utf8)) ?? ""
                } else {
                    do {
                        let plain = try CryptoVault.shared.decrypt(cipherText: config.configContent)
                        decrypted.configContent = plain
                    } catch {
                        logger.error("Failed to decrypt config '\(config.name)': \(error.localizedDescription)")
                    }
                }
                decryptedList.append(decrypted)
            }
            list.append(contentsOf: decryptedList)
        } catch {
            logger.error("Failed to fetch KubeConfigs from database: \(error.localizedDescription)")
        }

        return list
    }

    /// Context name to pass to kubectl for the selected kubeconfig.
    public func resolvedValidationContext(storedProviderContext: String?) -> String {
        guard let configID = selectedKubeConfigID,
              let config = availableKubeConfigs.first(where: { $0.id == configID }) else {
            return ""
        }
        return KubeConfigYAMLParser.resolveContextName(stored: storedProviderContext, in: config.resolvedPlainYAML()) ?? ""
    }

    /// Provider field value that matches `availableContexts` after a kubeconfig switch.
    public func sanitizedProviderContext(storedProviderContext: String?) -> String? {
        let resolved = resolvedValidationContext(storedProviderContext: storedProviderContext)
        return resolved.isEmpty ? nil : resolved
    }

    private func reloadDefaultKubeConfigContentIfNeeded() {
        guard selectedKubeConfigID == KubeConfig.defaultID,
              let index = availableKubeConfigs.firstIndex(where: { $0.id == KubeConfig.defaultID }) else {
            return
        }
        let customPath = KumaSettingsKey.string(
            forKey: KumaSettingsKey.customKubeconfigPath,
            fallbackKey: KumaSettingsKey.legacyKubeconfigPath,
            defaults: userDefaults
        )
        let path = DependencyChecker.resolvedKubeconfigPath(customPath: customPath)
            ?? DependencyChecker.standardKubeconfigFilePath()
        guard FileManager.default.fileExists(atPath: path) else { return }
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        availableKubeConfigs[index].configContent = content
        availableKubeConfigs[index].sourceFilePath = path
    }

    /// Extract context names from the currently selected kubeconfig YAML content
    public func refreshContextsForCurrentConfig() {
        guard let configID = selectedKubeConfigID,
              let config = availableKubeConfigs.first(where: { $0.id == configID }) else {
            self.availableContexts = []
            self.activeContextName = nil
            return
        }
        let yaml = config.resolvedPlainYAML()
        self.activeContextName = KubeConfigYAMLParser.parseCurrentContext(fromYaml: yaml)
        self.availableContexts = KubeConfigYAMLParser.parseContexts(fromYaml: yaml)
    }

    public func inferredSourceMode(path: String, yaml: String) -> KumaDualSourceMode {
        KumaDualSourceMode.inferred(path: path, text: yaml, fallback: .chooseFile)
    }

    public func isSaveDisabled(sourceMode: KumaDualSourceMode, draftPath: String, draftYAML: String) -> Bool {
        let name = newKubeConfigName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return true }
        switch sourceMode {
        case .chooseFile:
            let path = draftPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return true }
            let expanded = NSString(string: path).expandingTildeInPath
            return !FileManager.default.fileExists(atPath: expanded)
        case .pasteYAML:
            return draftYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func resetNewConfigForm() {
        newKubeConfigName = ""
        newKubeConfigContent = ""
        newKubeConfigSourcePath = ""
        editingKubeConfigID = nil
    }

    public func beginEditing(config: KubeConfig) {
        newKubeConfigName = config.name
        editingKubeConfigID = config.id
        if let path = config.sourceFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            newKubeConfigSourcePath = path
            newKubeConfigContent = ""
        } else {
            newKubeConfigSourcePath = ""
            newKubeConfigContent = config.configContent
        }
    }

    public nonisolated static func parseCurrentContext(fromYaml yaml: String) -> String? {
        KubeConfigYAMLParser.parseCurrentContext(fromYaml: yaml)
    }

    public nonisolated static func parseContexts(fromYaml yaml: String) -> [String] {
        KubeConfigYAMLParser.parseContexts(fromYaml: yaml)
    }

    public func saveConfig(sourceMode: KumaDualSourceMode) async {
        let name = newKubeConfigName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let encryptedContent: String
        let sourcePath: String?

        do {
            switch sourceMode {
            case .chooseFile:
                let rawPath = newKubeConfigSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawPath.isEmpty else { return }
                let expanded = NSString(string: rawPath).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: expanded) else { return }
                encryptedContent = try CryptoVault.shared.encrypt(plainText: "")
                sourcePath = rawPath
            case .pasteYAML:
                let plainContent = newKubeConfigContent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !plainContent.isEmpty else { return }
                encryptedContent = try CryptoVault.shared.encrypt(plainText: plainContent)
                sourcePath = nil
            }

            let savedID: UUID
            let now = Date()
            if let editID = editingKubeConfigID,
               let existing = try await repo.fetch(id: editID) {
                let updated = KubeConfig(
                    id: editID,
                    name: name,
                    configContent: encryptedContent,
                    sourceFilePath: sourcePath,
                    createdAt: existing.createdAt,
                    updatedAt: now
                )
                try await repo.update(updated)
                savedID = editID
            } else {
                let newID = UUID()
                let newConfig = KubeConfig(
                    id: newID,
                    name: name,
                    configContent: encryptedContent,
                    sourceFilePath: sourcePath,
                    createdAt: now,
                    updatedAt: now
                )
                try await repo.insert(newConfig)
                savedID = newID
            }

            self.selectedKubeConfigID = savedID
            await loadConfigs()
            triggerBackgroundValidation(forceRefresh: true)

            showInlineNewConfigForm = false
            resetNewConfigForm()
        } catch {
            Self.logger.error("Failed to encrypt/save KubeConfig: \(error.localizedDescription)")
        }
    }

    public func deleteConfig() async {
        guard let id = selectedKubeConfigID, id != KubeConfig.defaultID else { return }
        do {
            try await repo.delete(id: id)
            selectedKubeConfigID = availableKubeConfigs.first?.id
            await loadConfigs()
        } catch {
            Self.logger.error("Failed to delete KubeConfig \(id): \(error.localizedDescription)")
        }
    }

    // MARK: - Non-blocking Background Validation & Caching

    public func triggerBackgroundValidation(storedProviderContext: String? = nil, forceRefresh: Bool = false) {
        activeValidationTask?.cancel()

        guard let configID = selectedKubeConfigID,
              let config = availableKubeConfigs.first(where: { $0.id == configID }) else {
            self.connectionError = nil
            self.connectionSuccess = false
            self.isLoadingNamespaces = false
            return
        }

        let content = config.resolvedPlainYAML()
        let validationContext = resolvedValidationContext(storedProviderContext: storedProviderContext)
        self.isLoadingNamespaces = true
        self.connectionError = nil
        self.connectionSuccess = false

        activeValidationTask = Task {
            let result = await KubeConnectionValidator.shared.validateConnection(
                configContent: content,
                context: validationContext,
                forceRefresh: forceRefresh
            )

            guard !Task.isCancelled else { return }
            guard self.selectedKubeConfigID == configID else { return }

            self.isLoadingNamespaces = false
            if result.isReachable {
                self.connectionSuccess = true
                self.connectionError = nil
            } else {
                self.connectionSuccess = false
                self.connectionError = result.errorMessage ?? "Unable to reach cluster"
            }
        }
    }

    public func testConnection(storedProviderContext: String? = nil) {
        triggerBackgroundValidation(storedProviderContext: storedProviderContext, forceRefresh: true)
    }
}
