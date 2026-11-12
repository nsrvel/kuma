import SwiftUI

/// Contextual status banner in Inspector with optional Live Logs CTA.
public struct InspectorRunningBanner: View {
    public let runtime: ServiceRuntimeState
    public let isDisabled: Bool
    public var crashDetail: String?
    public var configurationIssues: [ConfigurationIssue]
    public let onViewLogs: () -> Void

    public init(
        runtime: ServiceRuntimeState,
        isDisabled: Bool = false,
        crashDetail: String? = nil,
        configurationIssues: [ConfigurationIssue] = [],
        onViewLogs: @escaping () -> Void
    ) {
        self.runtime = runtime
        self.isDisabled = isDisabled
        self.crashDetail = crashDetail
        self.configurationIssues = configurationIssues
        self.onViewLogs = onViewLogs
    }

    private var blockingConfigurationIssues: [ConfigurationIssue] {
        configurationIssues.filter { $0.severity == .blocking }
    }

    private var configurationSubtitle: String? {
        guard let first = blockingConfigurationIssues.first else { return nil }
        let extra = blockingConfigurationIssues.count - 1
        if extra > 0 {
            return "\(first.message) (+\(extra) more)"
        }
        return first.message
    }

    private var isTransitional: Bool {
        runtime.isLoading || runtime.status == .starting || runtime.status == .stopping || runtime.status == .reconnecting
    }

    public var body: some View {
        if isDisabled {
            InspectorStatusPillBanner(
                title: "Disabled",
                subtitle: "Turn on in Options to run or edit.",
                tone: KumaStatus.disabledIndicator,
                washStrength: 0
            )
        } else {
            switch runtime.status {
            case .running:
                statusBanner(
                    title: "Running",
                    subtitle: "Settings are read-only while active.",
                    status: .running,
                    onViewLogs: onViewLogs
                )
            case .starting:
                statusBanner(
                    title: "Starting…",
                    subtitle: "Bringing the runner online.",
                    status: .starting,
                    onViewLogs: onViewLogs
                )
            case .reconnecting:
                statusBanner(
                    title: runtime.statusTitle,
                    subtitle: "Connection dropped — trying again.",
                    status: .reconnecting,
                    onViewLogs: onViewLogs
                )
            case .stopping:
                statusBanner(
                    title: "Stopping…",
                    subtitle: "Waiting for a clean shutdown.",
                    status: .stopping
                )
            case .crashed:
                let crashLine = crashDetail?
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map(String.init)
                statusBanner(
                    title: "Crashed",
                    subtitle: crashLine ?? configurationSubtitle ?? "Open Live Logs for details.",
                    status: .crashed,
                    washStrength: 0.12,
                    onViewLogs: onViewLogs
                )
            case .stopped:
                if let configSubtitle = configurationSubtitle {
                    InspectorStatusPillBanner(
                        title: "Can't start yet",
                        subtitle: configSubtitle,
                        tone: KumaStatus.failedIndicator,
                        washStrength: 0.12,
                        onViewLogs: onViewLogs
                    )
                } else {
                    statusBanner(
                        title: "Stopped",
                        subtitle: "You can edit all settings.",
                        status: .stopped,
                        onViewLogs: onViewLogs
                    )
                }
            }
        }
    }

    private func statusBanner(
        title: String,
        subtitle: String,
        status: ServiceState,
        washStrength: Double = 0.10,
        onViewLogs: (() -> Void)? = nil
    ) -> InspectorStatusPillBanner {
        InspectorStatusPillBanner(
            title: title,
            subtitle: subtitle,
            tone: KumaStatus.indicatorColor(for: status),
            showsOrbit: isTransitional,
            showsGlow: status == .running && !isTransitional,
            washStrength: washStrength,
            onViewLogs: onViewLogs
        )
    }
}
