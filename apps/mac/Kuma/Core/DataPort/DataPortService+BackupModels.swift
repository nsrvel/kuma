import Foundation

extension DataPortService {
    // MARK: - Backup Payload (100% V3 JSON Compatible)

    public struct KumaBackup: Codable, Sendable, Identifiable {
        public var id: String { "\(version)_\(exportedAt.timeIntervalSince1970)_\(workspaces.count)" }
        public let version: Int
        public let exportedAt: Date
        public let workspaces: [Workspace]
        public let workspaceImages: [String: String]? // [workspaceID: Base64PNG]
        public let groups: [ServiceGroup]?
        public let services: [ExportService]
        public let providers: [ExportProvider]
        public let portMappings: [ExportPortMapping]
        public let kubeConfigs: [ExportKubeConfig]

        public nonisolated init(
            version: Int? = nil,
            exportedAt: Date = Date(),
            workspaces: [Workspace] = [],
            workspaceImages: [String: String]? = nil,
            groups: [ServiceGroup]? = nil,
            services: [ExportService] = [],
            providers: [ExportProvider] = [],
            portMappings: [ExportPortMapping] = [],
            kubeConfigs: [ExportKubeConfig] = []
        ) {
            self.version = version ?? DataPortService.currentVersion
            self.exportedAt = exportedAt
            self.workspaces = workspaces
            self.workspaceImages = workspaceImages
            self.groups = groups
            self.services = services
            self.providers = providers
            self.portMappings = portMappings
            self.kubeConfigs = kubeConfigs
        }
    }

    public struct ExportService: Codable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let icon: String?
        public let colorHex: String?
        public let description: String?
        public let activeProviderID: UUID?
        public let workspaceID: UUID?
        public let groupIDs: [UUID]?
        public let isDisabled: Bool?
        public let isStarred: Bool?

        public nonisolated init(
            id: UUID = UUID(),
            name: String,
            icon: String? = nil,
            colorHex: String? = nil,
            description: String? = nil,
            activeProviderID: UUID? = nil,
            workspaceID: UUID? = nil,
            groupIDs: [UUID]? = nil,
            isDisabled: Bool? = false,
            isStarred: Bool? = false
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.colorHex = colorHex
            self.description = description
            self.activeProviderID = activeProviderID
            self.workspaceID = workspaceID
            self.groupIDs = groupIDs
            self.isDisabled = isDisabled
            self.isStarred = isStarred
        }
    }

    /// Single-service complete standalone export structure (for clipboard JSON copying & sharing)
    public struct SingleServiceExport: Codable, Sendable, Identifiable {
        public let version: Int
        public let exportedAt: Date
        public let service: ExportService
        public let providers: [ExportProvider]
        public let portMappings: [ExportPortMapping]
        public let kubeConfigs: [ExportKubeConfig]

        public var id: UUID { service.id }

        public nonisolated init(
            version: Int = DataPortService.currentVersion,
            exportedAt: Date = Date(),
            service: ExportService,
            providers: [ExportProvider],
            portMappings: [ExportPortMapping],
            kubeConfigs: [ExportKubeConfig] = []
        ) {
            self.version = version
            self.exportedAt = exportedAt
            self.service = service
            self.providers = providers
            self.portMappings = portMappings
            self.kubeConfigs = kubeConfigs
        }

        public nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            exportedAt = try container.decode(Date.self, forKey: .exportedAt)
            service = try container.decode(ExportService.self, forKey: .service)
            providers = try container.decode([ExportProvider].self, forKey: .providers)
            portMappings = try container.decode([ExportPortMapping].self, forKey: .portMappings)
            kubeConfigs = try container.decodeIfPresent([ExportKubeConfig].self, forKey: .kubeConfigs) ?? []
        }
    }

    public struct ExportProvider: Codable, Sendable, Identifiable {
        public let id: UUID
        public let serviceID: UUID
        public let type: String
        public let label: String?
        public let kubeConfigID: UUID?
        public let customKubeConfigPath: String?
        public let kubeContext: String?
        public let kubeNamespace: String?
        public let targetName: String?
        public let kubeTargetType: String?
        public let usePattern: Bool?
        public let yamlConfig: String?
        public let composeFilePath: String?
        public let initialScript: String?
        public let initialScriptPath: String?
        public let runCommand: String?
        public let workingDirectory: String?
        public let sshHost: String?
        public let sshUser: String?
        public let sshPort: Int?
        public let sshKeyPath: String?
        public let sshPassword: String?
        public let httpCheckUrl: String?
        public let httpCheckInterval: Int?
        public let tunnelType: String?
        public let tunnelTargetUrl: String?
        public let ngrokAuthToken: String?
        public let monitorProcessName: String?
        public let monitorInterval: Int?
        public let autoReconnect: Bool?

        public nonisolated init(
            id: UUID = UUID(),
            serviceID: UUID,
            type: String,
            label: String? = nil,
            runCommand: String? = nil,
            yamlConfig: String? = nil,
            composeFilePath: String? = nil,
            kubeContext: String? = nil,
            kubeNamespace: String? = nil,
            targetName: String? = nil,
            kubeConfigID: UUID? = nil,
            customKubeConfigPath: String? = nil,
            kubeTargetType: String? = nil,
            usePattern: Bool? = nil,
            initialScript: String? = nil,
            initialScriptPath: String? = nil,
            workingDirectory: String? = nil,
            sshHost: String? = nil,
            sshUser: String? = nil,
            sshPort: Int? = nil,
            sshKeyPath: String? = nil,
            sshPassword: String? = nil,
            httpCheckUrl: String? = nil,
            httpCheckInterval: Int? = nil,
            tunnelType: String? = nil,
            tunnelTargetUrl: String? = nil,
            ngrokAuthToken: String? = nil,
            monitorProcessName: String? = nil,
            monitorInterval: Int? = nil,
            autoReconnect: Bool? = nil
        ) {
            self.id = id
            self.serviceID = serviceID
            self.type = type
            self.label = label
            self.runCommand = runCommand
            self.yamlConfig = yamlConfig
            self.composeFilePath = composeFilePath
            self.kubeContext = kubeContext
            self.kubeNamespace = kubeNamespace
            self.targetName = targetName
            self.kubeConfigID = kubeConfigID
            self.customKubeConfigPath = customKubeConfigPath
            self.kubeTargetType = kubeTargetType
            self.usePattern = usePattern
            self.initialScript = initialScript
            self.initialScriptPath = initialScriptPath
            self.workingDirectory = workingDirectory
            self.sshHost = sshHost
            self.sshUser = sshUser
            self.sshPort = sshPort
            self.sshKeyPath = sshKeyPath
            self.sshPassword = sshPassword
            self.httpCheckUrl = httpCheckUrl
            self.httpCheckInterval = httpCheckInterval
            self.tunnelType = tunnelType
            self.tunnelTargetUrl = tunnelTargetUrl
            self.ngrokAuthToken = ngrokAuthToken
            self.monitorProcessName = monitorProcessName
            self.monitorInterval = monitorInterval
            self.autoReconnect = autoReconnect
        }


        public nonisolated var category: ProviderCategory {
            switch type {
            case "kube_port_forward", "kubernetes":   return .kubernetes
            case "docker":                            return .docker
            case "podman":                            return .podman
            case "shell":                             return .shell
            case "ssh":                               return .ssh
            case "http_check", "httpCheck":           return .httpCheck
            case "tunnel":                            return .tunnel
            case "process_monitor", "processMonitor": return .processMonitor
            default:                                  return .docker
            }
        }

        public var resolvedTarget: String {
            switch category {
            case .docker, .podman:
                if let yaml = yamlConfig, let image = extractComposeImage(from: yaml) {
                    return image
                }
                if let label, !label.isEmpty {
                    return label
                }
                return category.sidebarLabel

            case .kubernetes:
                let target = targetName?.trimmingCharacters(in: .whitespaces) ?? ""
                if !target.isEmpty {
                    return target
                }
                return category.sidebarLabel

            case .shell:
                if let cmd = runCommand, !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                    return cmd.trimmingCharacters(in: .whitespaces)
                }
                return category.sidebarLabel

            case .ssh:
                if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
                    return label.trimmingCharacters(in: .whitespaces)
                }
                let host = sshHost?.trimmingCharacters(in: .whitespaces) ?? ""
                if !host.isEmpty {
                    return host
                }
                return category.sidebarLabel

            case .httpCheck:
                if let url = httpCheckUrl, !url.trimmingCharacters(in: .whitespaces).isEmpty {
                    return url.trimmingCharacters(in: .whitespaces)
                }
                return category.sidebarLabel

            case .tunnel:
                if let target = tunnelTargetUrl, !target.trimmingCharacters(in: .whitespaces).isEmpty {
                    return target.trimmingCharacters(in: .whitespaces)
                }
                return category.sidebarLabel

            case .processMonitor:
                if let proc = monitorProcessName, !proc.trimmingCharacters(in: .whitespaces).isEmpty {
                    return proc.trimmingCharacters(in: .whitespaces)
                }
                return category.sidebarLabel
            }
        }

        private func extractComposeImage(from yaml: String) -> String? {
            let lines = yaml.components(separatedBy: .newlines)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("image:") {
                    let rawImage = line.dropFirst("image:".count).trimmingCharacters(in: .whitespaces)
                    var cleaned = rawImage.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if cleaned.hasPrefix("docker.io/library/") {
                        cleaned = String(cleaned.dropFirst("docker.io/library/".count))
                    } else if cleaned.hasPrefix("docker.io/") {
                        cleaned = String(cleaned.dropFirst("docker.io/".count))
                    } else if cleaned.hasPrefix("library/") {
                        cleaned = String(cleaned.dropFirst("library/".count))
                    }
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
            return nil
        }
    }

    public struct ExportPortMapping: Codable, Sendable, Identifiable {
        public let id: UUID
        public let providerID: UUID
        public let localPort: Int
        public let remotePort: Int

        public nonisolated init(id: UUID = UUID(), providerID: UUID, localPort: Int, remotePort: Int) {
            self.id = id
            self.providerID = providerID
            self.localPort = localPort
            self.remotePort = remotePort
        }
    }

    public struct ExportKubeConfig: Codable, Sendable, Identifiable {
        public let id: UUID
        public let name: String?
        public let path: String?
        /// Vault ciphertext (`nonce:tag:ciphertext`), same as `kube_config.configContent` in SQLite.
        public let encryptedConfigContent: String?
        public let createdAt: Date?
        public let updatedAt: Date?

        public nonisolated init(
            id: UUID = UUID(),
            name: String? = nil,
            path: String? = nil,
            encryptedConfigContent: String? = nil,
            createdAt: Date? = nil,
            updatedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.encryptedConfigContent = encryptedConfigContent
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

}
