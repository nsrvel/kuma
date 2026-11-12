import Foundation
import GRDB

extension DataPortRepository {
    nonisolated static func collectReferencedKubeConfigIDs(from providers: [DataPortService.ExportProvider]) -> Set<UUID> {
        Set(providers.compactMap(\.kubeConfigID).filter { $0 != KubeConfig.defaultID })
    }

    nonisolated static func importKubeConfigs(_ configs: [DataPortService.ExportKubeConfig], db: Database) throws {
        for exportKube in configs {
            guard exportKube.id != KubeConfig.defaultID else { continue }
            let cipher = exportKube.encryptedConfigContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let path = exportKube.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cipher.isEmpty || !path.isEmpty else { continue }

            let createdAt = exportKube.createdAt ?? Date()
            let updatedAt = exportKube.updatedAt ?? Date()
            let storedCipher = cipher.isEmpty ? "" : cipher
            let storedPath: String? = path.isEmpty ? nil : path
            try db.execute(
                sql: """
                INSERT INTO kube_config (id, name, configContent, sourceFilePath, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    configContent = excluded.configContent,
                    sourceFilePath = excluded.sourceFilePath,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    exportKube.id.uuidString,
                    exportKube.name ?? "Imported",
                    storedCipher,
                    storedPath,
                    createdAt,
                    updatedAt
                ]
            )
        }
    }

    public nonisolated static func toExportProvider(_ p: Provider) throws -> DataPortService.ExportProvider {
        let encryptedPassword: String?
        if let pass = p.sshPassword, !pass.isEmpty {
            encryptedPassword = try CredentialProtector.encryptForStorage(pass)
        } else {
            encryptedPassword = nil
        }

        let encryptedToken: String?
        if let token = p.ngrokAuthToken, !token.isEmpty {
            encryptedToken = try CredentialProtector.encryptForStorage(token)
        } else {
            encryptedToken = nil
        }

        return DataPortService.ExportProvider(
            id: p.id,
            serviceID: p.serviceID,
            type: p.type.rawValue,
            label: p.label,
            runCommand: p.runCommand,
            yamlConfig: p.yamlConfig,
            composeFilePath: p.composeFilePath,
            kubeContext: p.kubeContext,
            kubeNamespace: p.kubeNamespace,
            targetName: p.targetName,
            kubeConfigID: p.kubeConfigID,
            customKubeConfigPath: p.customKubeConfigPath,
            kubeTargetType: p.kubeTargetType,
            usePattern: p.usePattern,
            initialScript: p.initialScript,
            initialScriptPath: p.initialScriptPath,
            workingDirectory: p.workingDirectory,
            sshHost: p.sshHost,
            sshUser: p.sshUser,
            sshPort: p.sshPort,
            sshKeyPath: p.sshKeyPath,
            sshPassword: encryptedPassword,
            httpCheckUrl: p.httpCheckUrl,
            httpCheckInterval: p.httpCheckInterval,
            tunnelType: p.tunnelType,
            tunnelTargetUrl: p.tunnelTargetUrl,
            ngrokAuthToken: encryptedToken,
            monitorProcessName: p.monitorProcessName,
            monitorInterval: p.monitorInterval,
            autoReconnect: p.autoReconnect
        )
    }

    public nonisolated static func fromExportProvider(_ p: DataPortService.ExportProvider) -> Provider {
        let decryptedPassword: String?
        if let pass = p.sshPassword, !pass.isEmpty {
            decryptedPassword = (try? CryptoVault.shared.decrypt(cipherText: pass)) ?? pass
        } else {
            decryptedPassword = nil
        }

        let decryptedToken: String?
        if let token = p.ngrokAuthToken, !token.isEmpty {
            decryptedToken = (try? CryptoVault.shared.decrypt(cipherText: token)) ?? token
        } else {
            decryptedToken = nil
        }

        return Provider(
            id: p.id,
            serviceID: p.serviceID,
            type: p.category,
            label: p.label,
            kubeConfigID: p.kubeConfigID,
            customKubeConfigPath: p.customKubeConfigPath,
            kubeContext: p.kubeContext,
            kubeNamespace: p.kubeNamespace,
            targetName: p.targetName,
            kubeTargetType: p.kubeTargetType,
            usePattern: p.usePattern,
            yamlConfig: p.yamlConfig,
            composeFilePath: p.composeFilePath,
            initialScript: p.initialScript,
            initialScriptPath: p.initialScriptPath,
            runCommand: p.runCommand,
            workingDirectory: p.workingDirectory,
            sshHost: p.sshHost,
            sshUser: p.sshUser,
            sshPort: p.sshPort,
            sshKeyPath: p.sshKeyPath,
            sshPassword: decryptedPassword,
            httpCheckUrl: p.httpCheckUrl,
            httpCheckInterval: p.httpCheckInterval,
            tunnelType: p.tunnelType,
            tunnelTargetUrl: p.tunnelTargetUrl,
            ngrokAuthToken: decryptedToken,
            monitorProcessName: p.monitorProcessName,
            monitorInterval: p.monitorInterval,
            autoReconnect: p.autoReconnect
        )
    }

    /// Exports a single service along with its providers and port mappings as formatted JSON string.
}
