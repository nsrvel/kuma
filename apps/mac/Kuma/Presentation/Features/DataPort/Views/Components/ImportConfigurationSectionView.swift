import SwiftUI

public struct ImportConfigurationSectionView: View {
    public let provider: DataPortService.ExportProvider
    public let category: ProviderCategory

    public init(provider: DataPortService.ExportProvider, category: ProviderCategory) {
        self.provider = provider
        self.category = category
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONFIGURATION")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.secondary)

            detailRow(title: "Type", value: category.sidebarLabel)

            switch category {
            case .docker, .podman:
                let img = provider.resolvedTarget
                if img != category.sidebarLabel {
                    detailRow(title: "Image", value: img, isMono: true)
                }
                if let script = provider.initialScript, !script.isEmpty {
                    detailRow(title: "Init Script", value: script, isMono: true)
                }

            case .kubernetes:
                if let target = provider.targetName, !target.isEmpty {
                    detailRow(title: "Target", value: target, isMono: true)
                }
                if let ns = provider.kubeNamespace, !ns.isEmpty {
                    detailRow(title: "Namespace", value: ns)
                }
                if let ctx = provider.kubeContext, !ctx.isEmpty {
                    detailRow(title: "Context", value: ctx)
                }
                if let targetType = provider.kubeTargetType, !targetType.isEmpty {
                    detailRow(title: "Resource", value: targetType.capitalized)
                }

            case .shell:
                if let cmd = provider.runCommand, !cmd.isEmpty {
                    detailRow(title: "Command", value: cmd, isMono: true)
                }
                if let dir = provider.workingDirectory, !dir.isEmpty {
                    detailRow(title: "Working Dir", value: dir, isMono: true)
                }

            case .ssh:
                if let host = provider.sshHost, !host.isEmpty {
                    detailRow(title: "Host", value: "\(provider.sshUser ?? "root")@\(host):\(provider.sshPort ?? 22)", isMono: true)
                }
                if let key = provider.sshKeyPath, !key.isEmpty {
                    detailRow(title: "Identity Key", value: key, isMono: true)
                }

            case .httpCheck:
                if let url = provider.httpCheckUrl, !url.isEmpty {
                    detailRow(title: "Health URL", value: url, isMono: true)
                }
                if let interval = provider.httpCheckInterval {
                    detailRow(title: "Interval", value: "\(interval)s")
                }

            case .tunnel:
                if let target = provider.tunnelTargetUrl, !target.isEmpty {
                    detailRow(title: "Forward Target", value: target, isMono: true)
                }
                if let tType = provider.tunnelType, !tType.isEmpty {
                    detailRow(title: "Tunnel Provider", value: tType.capitalized)
                }

            case .processMonitor:
                if let proc = provider.monitorProcessName, !proc.isEmpty {
                    detailRow(title: "Process Name", value: proc, isMono: true)
                }
                if let interval = provider.monitorInterval {
                    detailRow(title: "Interval", value: "\(interval)s")
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(title: String, value: String, isMono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: isMono ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }
}
