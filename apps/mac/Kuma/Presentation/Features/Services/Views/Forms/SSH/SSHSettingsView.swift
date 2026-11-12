import SwiftUI

// MARK: - SSHAuthType

public enum SSHAuthType: String, CaseIterable, Identifiable, Sendable {
    case key = "SSH Key"
    case password = "Password"

    public var id: String { rawValue }
}

// MARK: - SSHSettingsView

/// Configuration view for SSH Remote Tunneling provider (Host, Port, User, Auth, Key/Password).
public struct SSHSettingsView: View {
    @Binding public var sshHost: String
    @Binding public var sshPort: String
    @Binding public var sshUser: String
    @Binding public var authType: SSHAuthType
    @Binding public var sshKeyPath: String
    @Binding public var sshPassword: String

    public init(
        sshHost: Binding<String>,
        sshPort: Binding<String>,
        sshUser: Binding<String>,
        authType: Binding<SSHAuthType>,
        sshKeyPath: Binding<String>,
        sshPassword: Binding<String>
    ) {
        self._sshHost = sshHost
        self._sshPort = sshPort
        self._sshUser = sshUser
        self._authType = authType
        self._sshKeyPath = sshKeyPath
        self._sshPassword = sshPassword
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Host and Port in responsive columns
            HStack(alignment: .top, spacing: 12) {
                KumaTextField(
                    label: "Remote Host",
                    value: $sshHost,
                    placeholder: "bastion.company.com"
                )

                KumaTextField(
                    label: "Port",
                    value: $sshPort,
                    placeholder: "22"
                )
                .frame(width: 80)
            }

            KumaTextField(
                label: "SSH User",
                value: $sshUser,
                placeholder: "ubuntu"
            )

            // Authentication Method Dropdown
            KumaRowPickerField(
                label: "Authentication",
                description: "Authentication method for remote host.",
                options: SSHAuthType.allCases,
                selection: $authType,
                titleResolver: { $0.rawValue }
            )

            Divider().opacity(0.3)

            if authType == .key {
                KumaFilePickerField(
                    label: "Private Key Path",
                    path: $sshKeyPath,
                    placeholder: "~/.ssh/id_ed25519",
                    chooseFiles: true,
                    chooseDirectories: false,
                    showsHiddenFiles: true
                )
            } else {
                KumaSecureField(
                    label: "SSH Password",
                    value: $sshPassword,
                    placeholder: "••••••••••••"
                )
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var host = "bastion.example.com"
        @State private var port = "22"
        @State private var user = "ubuntu"
        @State private var auth = SSHAuthType.key
        @State private var keyPath = "~/.ssh/id_ed25519"
        @State private var pass = ""

        var body: some View {
            KumaFormSection(
                icon: "network",
                title: "SSH Connection"
            ) {
                SSHSettingsView(
                    sshHost: $host,
                    sshPort: $port,
                    sshUser: $user,
                    authType: $auth,
                    sshKeyPath: $keyPath,
                    sshPassword: $pass
                )
            }
            .padding()
            .frame(width: 500)
            .background(KumaColors.canvasBackground)
        }
    }
    return PreviewWrapper()
}
