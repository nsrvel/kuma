import Foundation

enum ComposeStackResolver {
    struct Resolution: Sendable {
        let composeFilePath: String
        let workingDirectory: String
        let isEphemeralComposeFile: Bool
    }

    static func resolve(
        service: Service,
        provider: Provider,
        configuredWorkingDirectory: String?
    ) throws -> Resolution {
        if let rawPath = provider.composeFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else {
                throw ServiceExecutionError.invalidConfiguration("Compose file not found: \(rawPath)")
            }
            let workingDir = configuredWorkingDirectory ?? (expanded as NSString).deletingLastPathComponent
            return Resolution(composeFilePath: expanded, workingDirectory: workingDir, isEphemeralComposeFile: false)
        }

        if let yamlConfig = provider.yamlConfig?.trimmingCharacters(in: .whitespacesAndNewlines), !yamlConfig.isEmpty {
            let workingDir: String
            if let configuredWorkingDirectory {
                workingDir = configuredWorkingDirectory
            } else {
                let tempFolder = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("kuma-compose-\(service.id.uuidString)")
                try FileManager.default.createDirectory(atPath: tempFolder, withIntermediateDirectories: true)
                workingDir = tempFolder
            }
            let filePath = (workingDir as NSString).appendingPathComponent("docker-compose.kuma.yml")
            do {
                try yamlConfig.write(toFile: filePath, atomically: true, encoding: .utf8)
            } catch {
                throw ServiceExecutionError.processFailed("Failed to write compose YAML: \(error.localizedDescription)")
            }
            return Resolution(composeFilePath: filePath, workingDirectory: workingDir, isEphemeralComposeFile: true)
        }

        throw ServiceExecutionError.invalidConfiguration("No compose file or YAML configured")
    }

    static func configuredWorkingDirectory(from provider: Provider) -> String? {
        guard let rawDir = provider.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !rawDir.isEmpty else {
            return nil
        }
        let expanded = NSString(string: rawDir).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return expanded
    }

    static func makeContext(
        service: Service,
        provider: Provider,
        binaryPath: String
    ) throws -> ComposeStackContext {
        let workingDirOverride = configuredWorkingDirectory(from: provider)
        let resolution = try resolve(service: service, provider: provider, configuredWorkingDirectory: workingDirOverride)
        return ComposeStackContext(
            serviceID: service.id,
            binaryPath: binaryPath,
            composeFilePath: resolution.composeFilePath,
            workingDirectory: resolution.workingDirectory,
            projectName: ComposeStackContext.projectName(for: service.id),
            isEphemeralComposeFile: resolution.isEphemeralComposeFile
        )
    }
}
