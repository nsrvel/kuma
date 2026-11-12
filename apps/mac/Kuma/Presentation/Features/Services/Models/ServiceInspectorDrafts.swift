import Foundation

// MARK: - Presentation Draft Models for Service Inspector Form

public struct ServiceGeneralDraft: Equatable, Sendable {
    public var name: String
    public var description: String
    public var isDisabled: Bool

    public init(name: String = "", description: String = "", isDisabled: Bool = false) {
        self.name = name
        self.description = description
        self.isDisabled = isDisabled
    }
}

public struct ServiceKubernetesDraft: Equatable, Sendable {
    public var configID: UUID?
    public var namespace: String
    public var context: String
    public var targetName: String
    public var targetType: KubeTargetType
    public var usePattern: Bool

    public init(
        configID: UUID? = nil,
        namespace: String = "",
        context: String = "",
        targetName: String = "",
        targetType: KubeTargetType = .pod,
        usePattern: Bool = true
    ) {
        self.configID = configID
        self.namespace = namespace
        self.context = context
        self.targetName = targetName
        self.targetType = targetType
        self.usePattern = usePattern
    }
}

public struct ServiceComposeDraft: Equatable, Sendable {
    public var yamlConfig: String
    public var composeFilePath: String
    public var initialScript: String
    public var initialScriptPath: String

    public init(
        yamlConfig: String = "",
        composeFilePath: String = "",
        initialScript: String = "",
        initialScriptPath: String = ""
    ) {
        self.yamlConfig = yamlConfig
        self.composeFilePath = composeFilePath
        self.initialScript = initialScript
        self.initialScriptPath = initialScriptPath
    }
}

public struct ServiceShellDraft: Equatable, Sendable {
    public var runCommand: String
    public var workingDirectory: String

    public init(runCommand: String = "", workingDirectory: String = "") {
        self.runCommand = runCommand
        self.workingDirectory = workingDirectory
    }
}

public struct ServiceSSHDraft: Equatable, Sendable {
    public var host: String
    public var user: String
    public var port: String
    public var authType: SSHAuthType
    public var keyPath: String
    public var password: String

    public init(
        host: String = "",
        user: String = "",
        port: String = "22",
        authType: SSHAuthType = .key,
        keyPath: String = "~/.ssh/id_ed25519",
        password: String = ""
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.authType = authType
        self.keyPath = keyPath
        self.password = password
    }
}

public struct ServiceHealthCheckDraft: Equatable, Sendable {
    public var url: String
    public var interval: HealthCheckIntervalOption

    public init(url: String = "", interval: HealthCheckIntervalOption = .fast) {
        self.url = url
        self.interval = interval
    }
}

public struct ServiceTunnelDraft: Equatable, Sendable {
    public var engine: TunnelEngineOption
    public var targetUrl: String
    public var authToken: String

    public init(
        engine: TunnelEngineOption = .cloudflare,
        targetUrl: String = "http://localhost:3000",
        authToken: String = ""
    ) {
        self.engine = engine
        self.targetUrl = targetUrl
        self.authToken = authToken
    }
}

public struct ServiceProcessMonitorDraft: Equatable, Sendable {
    public var processName: String
    public var interval: HealthCheckIntervalOption

    public init(processName: String = "", interval: HealthCheckIntervalOption = .fast) {
        self.processName = processName
        self.interval = interval
    }
}
