import SwiftUI

public struct InspectorRemoteAndNetworkFormSections: View {
    @Binding public var provider: Provider
    @Binding public var sshAuthType: SSHAuthType
    public let isLocked: Bool
    public let onFieldChanged: () -> Void

    public var body: some View {
        Group {
            switch provider.type {
            case .shell:
                KumaFormSection(icon: "terminal.fill", title: "Shell Command") {
                    ShellScriptSettingsView(
                        runCommand: Binding(
                            get: { provider.runCommand ?? "" },
                            set: { provider.runCommand = $0; onFieldChanged() }
                        ),
                        workingDirectory: Binding(
                            get: { provider.workingDirectory ?? "" },
                            set: { provider.workingDirectory = $0.isEmpty ? nil : $0; onFieldChanged() }
                        )
                    )
                    .disabled(isLocked)
                }

            case .ssh:
                KumaFormSection(icon: "network", title: "SSH Connection") {
                    SSHSettingsView(
                        sshHost: Binding(
                            get: { provider.sshHost ?? "" },
                            set: { provider.sshHost = $0.isEmpty ? nil : $0; onFieldChanged() }
                        ),
                        sshPort: Binding(
                            get: { provider.sshPort != nil ? "\(provider.sshPort!)" : "22" },
                            set: { provider.sshPort = Int($0) ?? 22; onFieldChanged() }
                        ),
                        sshUser: Binding(
                            get: { provider.sshUser ?? "" },
                            set: { provider.sshUser = $0.isEmpty ? nil : $0; onFieldChanged() }
                        ),
                        authType: Binding(
                            get: { sshAuthType },
                            set: { newType in
                                sshAuthType = newType
                                ProviderSSHAuth.applyAuthTypeChange(newType, to: &provider)
                                onFieldChanged()
                            }
                        ),
                        sshKeyPath: Binding(
                            get: { provider.sshKeyPath ?? "~/.ssh/id_ed25519" },
                            set: { provider.sshKeyPath = $0; onFieldChanged() }
                        ),
                        sshPassword: Binding(
                            get: { provider.sshPassword ?? "" },
                            set: { provider.sshPassword = $0; onFieldChanged() }
                        )
                    )
                    .disabled(isLocked)
                }

            case .httpCheck:
                KumaFormSection(icon: "heart.text.square.fill", title: "Health Check") {
                    HealthCheckSettingsView(
                        httpCheckUrl: Binding(
                            get: { provider.httpCheckUrl ?? "" },
                            set: { provider.httpCheckUrl = $0; onFieldChanged() }
                        ),
                        checkInterval: Binding(
                            get: { HealthCheckIntervalOption(rawValue: provider.httpCheckInterval ?? 5) ?? .fast },
                            set: { provider.httpCheckInterval = $0.rawValue; onFieldChanged() }
                        )
                    )
                    .disabled(isLocked)
                }

            case .tunnel:
                KumaFormSection(icon: "cloud.bolt.fill", title: "Public Tunnel") {
                    TunnelSettingsView(
                        tunnelType: Binding(
                            get: { TunnelEngineOption(rawValue: provider.tunnelType ?? "cloudflare") ?? .cloudflare },
                            set: { provider.tunnelType = $0.rawValue; onFieldChanged() }
                        ),
                        tunnelTargetUrl: Binding(
                            get: { provider.tunnelTargetUrl ?? "http://localhost:3000" },
                            set: { provider.tunnelTargetUrl = $0; onFieldChanged() }
                        ),
                        ngrokAuthToken: Binding(
                            get: { provider.ngrokAuthToken ?? "" },
                            set: { provider.ngrokAuthToken = $0.isEmpty ? nil : $0; onFieldChanged() }
                        )
                    )
                    .disabled(isLocked)
                }

            case .processMonitor:
                KumaFormSection(icon: "cpu.fill", title: "Process Monitor") {
                    ProcessMonitorSettingsView(
                        monitorProcessName: Binding(
                            get: { provider.monitorProcessName ?? "" },
                            set: { provider.monitorProcessName = $0; onFieldChanged() }
                        ),
                        monitorInterval: Binding(
                            get: { HealthCheckIntervalOption(rawValue: provider.monitorInterval ?? 5) ?? .fast },
                            set: { provider.monitorInterval = $0.rawValue; onFieldChanged() }
                        )
                    )
                    .disabled(isLocked)
                }

            default:
                EmptyView()
            }
        }
    }
}
