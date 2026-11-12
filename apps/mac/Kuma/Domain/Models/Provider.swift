import Foundation

public nonisolated struct Provider: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var serviceID: UUID
    public var type: ProviderCategory
    public var label: String?

    // Kubernetes Port Forward
    public var kubeConfigID: UUID?
    public var customKubeConfigPath: String?
    public var kubeContext: String?
    public var kubeNamespace: String?
    public var targetName: String?
    public var kubeTargetType: String?
    public var usePattern: Bool?

    // Docker & Podman Compose
    public var yamlConfig: String?
    public var composeFilePath: String?
    public var initialScript: String?
    public var initialScriptPath: String?

    // Shell Execution
    public var runCommand: String?
    public var workingDirectory: String?

    // SSH Remote
    public var sshHost: String?
    public var sshUser: String?
    public var sshPort: Int?
    public var sshKeyPath: String?
    public var sshPassword: String?

    // Health Check & Public Tunnel
    public var httpCheckUrl: String?
    public var httpCheckInterval: Int?
    public var tunnelType: String?
    public var tunnelTargetUrl: String?
    public var ngrokAuthToken: String?

    // Process Monitor
    public var monitorProcessName: String?
    public var monitorInterval: Int?

    /// When true, unexpected managed-process disconnects trigger automatic reconnect (Kubernetes, SSH, Shell).
    public var autoReconnect: Bool?

    public var createdAt: Date
    public var updatedAt: Date

    public nonisolated init(
        id: UUID = UUID(),
        serviceID: UUID,
        type: ProviderCategory,
        label: String? = nil,
        kubeConfigID: UUID? = nil,
        customKubeConfigPath: String? = nil,
        kubeContext: String? = nil,
        kubeNamespace: String? = nil,
        targetName: String? = nil,
        kubeTargetType: String? = nil,
        usePattern: Bool? = nil,
        yamlConfig: String? = nil,
        composeFilePath: String? = nil,
        initialScript: String? = nil,
        initialScriptPath: String? = nil,
        runCommand: String? = nil,
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
        autoReconnect: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serviceID = serviceID
        self.type = type
        self.label = label
        self.kubeConfigID = kubeConfigID
        self.customKubeConfigPath = customKubeConfigPath
        self.kubeContext = kubeContext
        self.kubeNamespace = kubeNamespace
        self.targetName = targetName
        self.kubeTargetType = kubeTargetType
        self.usePattern = usePattern
        self.yamlConfig = yamlConfig
        self.composeFilePath = composeFilePath
        self.initialScript = initialScript
        self.initialScriptPath = initialScriptPath
        self.runCommand = runCommand
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public nonisolated var isAutoReconnectEnabled: Bool {
        autoReconnect == true && type.supportsAutoReconnect
    }

    public nonisolated var displayName: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
            return label
        }
        return type.sidebarLabel
    }

    /// Computes the exact contextual target string for the card UI (e.g. image name, kube target, command, url).
    public nonisolated var resolvedTarget: String {
        switch type {
        case .docker:
            if let path = composeFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return "Docker: \((path as NSString).lastPathComponent)"
            }
            if let yaml = yamlConfig, let image = extractComposeImage(from: yaml) {
                return "Docker: \(image)"
            }
            if let label, !label.isEmpty {
                return "Docker: \(label)"
            }
            return "Docker"

        case .podman:
            if let path = composeFilePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return "Podman: \((path as NSString).lastPathComponent)"
            }
            if let yaml = yamlConfig, let image = extractComposeImage(from: yaml) {
                return "Podman: \(image)"
            }
            if let label, !label.isEmpty {
                return "Podman: \(label)"
            }
            return "Podman"

        case .kubernetes:
            if let target = targetName?.trimmingCharacters(in: .whitespaces), !target.isEmpty {
                return "k8s: \(target)"
            }
            return "Kubernetes"


        case .shell:
            if let cmd = runCommand, !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                return cmd.trimmingCharacters(in: .whitespaces)
            }
            return "Shell script"

        case .ssh:
            let user = sshUser ?? "root"
            let host = sshHost ?? "localhost"
            let port = sshPort ?? 22
            return "SSH: \(user)@\(host):\(port)"

        case .httpCheck:
            if let url = httpCheckUrl, !url.trimmingCharacters(in: .whitespaces).isEmpty {
                return "HTTP: \(url.trimmingCharacters(in: .whitespaces))"
            }
            return "HTTP Check"

        case .tunnel:
            let engine = (tunnelType ?? "cloudflare").capitalized
            let target = tunnelTargetUrl ?? "8080"
            return "\(engine) Tunnel -> \(target)"

        case .processMonitor:
            if let proc = monitorProcessName, !proc.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Monitor: \(proc)"
            }
            return "Process Monitor"
        }
    }


    /// Fast single-pass scanner to extract `image: ...` from Docker/Podman compose YAML and normalize to short image:tag
    private nonisolated func extractComposeImage(from yaml: String) -> String? {
        let lines = yaml.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("image:") {
                let rawImage = line.dropFirst("image:".count).trimmingCharacters(in: .whitespaces)
                var cleaned = rawImage.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                
                // Strip common bloated registry prefixes:
                // e.g. "docker.io/library/mongo:7" -> "mongo:7"
                // e.g. "docker.io/redis:alpine" -> "redis:alpine"
                // e.g. "library/postgres:16" -> "postgres:16"
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
