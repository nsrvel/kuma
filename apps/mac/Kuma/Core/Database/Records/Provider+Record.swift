import Foundation
import GRDB

// MARK: - Provider GRDB Record Conformance

nonisolated extension Provider: FetchableRecord, PersistableRecord {
    public nonisolated static let databaseTableName = "provider"

    public nonisolated init(row: Row) throws {
        let idStr: String = row["id"]
        let id = UUID(uuidString: idStr) ?? UUID()
        let serviceStr: String = row["serviceID"]
        let serviceID = UUID(uuidString: serviceStr) ?? UUID()
        let typeRaw: String = row["type"]
        let type = ProviderCategory(rawValue: typeRaw) ?? .docker
        let label: String? = row["label"]

        let kubeConfigStr: String? = row["kubeConfigID"]
        let kubeConfigID = kubeConfigStr.flatMap(UUID.init)
        let customKubeConfigPath: String? = row["customKubeConfigPath"]
        let kubeContext: String? = row["kubeContext"]
        let kubeNamespace: String? = row["kubeNamespace"]
        let targetName: String? = row["targetName"]
        let kubeTargetType: String? = row["kubeTargetType"]
        let usePattern: Bool? = row["usePattern"]

        let yamlConfig: String? = row["yamlConfig"]
        let composeFilePath: String? = row["composeFilePath"]
        let initialScript: String? = row["initialScript"]
        let initialScriptPath: String? = row["initialScriptPath"]

        let runCommand: String? = row["runCommand"]
        let workingDirectory: String? = row["workingDirectory"]

        let sshHost: String? = row["sshHost"]
        let sshUser: String? = row["sshUser"]
        let sshPort: Int? = row["sshPort"]
        let sshKeyPath: String? = row["sshKeyPath"]
        let rawSshPassword: String? = row["sshPassword"]
        let sshPassword: String?
        if let rawSshPassword, !rawSshPassword.isEmpty {
            // Decrypt if stored as encrypted vault string, otherwise maintain plaintext backward-compat
            sshPassword = (try? CryptoVault.shared.decrypt(cipherText: rawSshPassword)) ?? rawSshPassword
        } else {
            sshPassword = nil
        }

        let httpCheckUrl: String? = row["httpCheckUrl"]
        let httpCheckInterval: Int? = row["httpCheckInterval"]
        let tunnelType: String? = row["tunnelType"]
        let tunnelTargetUrl: String? = row["tunnelTargetUrl"]
        let rawNgrokToken: String? = row["ngrokAuthToken"]
        let ngrokAuthToken: String?
        if let rawNgrokToken, !rawNgrokToken.isEmpty {
            // Decrypt if stored as encrypted vault string, otherwise maintain plaintext backward-compat
            ngrokAuthToken = (try? CryptoVault.shared.decrypt(cipherText: rawNgrokToken)) ?? rawNgrokToken
        } else {
            ngrokAuthToken = nil
        }

        let monitorProcessName: String? = row["monitorProcessName"]
        let monitorInterval: Int? = row["monitorInterval"]
        let autoReconnect: Bool? = row["autoReconnect"]

        let createdAt: Date = row["createdAt"]
        let updatedAt: Date = row["updatedAt"]

        self.init(
            id: id,
            serviceID: serviceID,
            type: type,
            label: label,
            kubeConfigID: kubeConfigID,
            customKubeConfigPath: customKubeConfigPath,
            kubeContext: kubeContext,
            kubeNamespace: kubeNamespace,
            targetName: targetName,
            kubeTargetType: kubeTargetType,
            usePattern: usePattern,
            yamlConfig: yamlConfig,
            composeFilePath: composeFilePath,
            initialScript: initialScript,
            initialScriptPath: initialScriptPath,
            runCommand: runCommand,
            workingDirectory: workingDirectory,
            sshHost: sshHost,
            sshUser: sshUser,
            sshPort: sshPort,
            sshKeyPath: sshKeyPath,
            sshPassword: sshPassword,
            httpCheckUrl: httpCheckUrl,
            httpCheckInterval: httpCheckInterval,
            tunnelType: tunnelType,
            tunnelTargetUrl: tunnelTargetUrl,
            ngrokAuthToken: ngrokAuthToken,
            monitorProcessName: monitorProcessName,
            monitorInterval: monitorInterval,
            autoReconnect: autoReconnect,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["serviceID"] = serviceID.uuidString
        container["type"] = type.rawValue
        container["label"] = label
        container["kubeConfigID"] = kubeConfigID?.uuidString
        container["customKubeConfigPath"] = customKubeConfigPath
        container["kubeContext"] = kubeContext
        container["kubeNamespace"] = kubeNamespace
        container["targetName"] = targetName
        container["kubeTargetType"] = kubeTargetType
        container["usePattern"] = usePattern
        container["yamlConfig"] = yamlConfig
        container["composeFilePath"] = composeFilePath
        container["initialScript"] = initialScript
        container["initialScriptPath"] = initialScriptPath
        container["runCommand"] = runCommand
        container["workingDirectory"] = workingDirectory
        container["sshHost"] = sshHost
        container["sshUser"] = sshUser
        container["sshPort"] = sshPort
        container["sshKeyPath"] = sshKeyPath

        // Secure encryption for sensitive credentials before persisting to SQLite
        if let pass = sshPassword, !pass.isEmpty {
            container["sshPassword"] = try CredentialProtector.encryptForStorage(pass)
        } else {
            container["sshPassword"] = nil
        }

        container["httpCheckUrl"] = httpCheckUrl
        container["httpCheckInterval"] = httpCheckInterval
        container["tunnelType"] = tunnelType
        container["tunnelTargetUrl"] = tunnelTargetUrl

        if let token = ngrokAuthToken, !token.isEmpty {
            container["ngrokAuthToken"] = try CredentialProtector.encryptForStorage(token)
        } else {
            container["ngrokAuthToken"] = nil
        }

        container["monitorProcessName"] = monitorProcessName
        container["monitorInterval"] = monitorInterval
        container["autoReconnect"] = autoReconnect ?? false
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }
}
