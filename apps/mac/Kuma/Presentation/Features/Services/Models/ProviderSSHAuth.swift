import Foundation

/// Inspector/create SSH auth field normalization (RUN-04).
public enum ProviderSSHAuth {
    public static func inferredAuthType(for provider: Provider) -> SSHAuthType {
        let pass = provider.sshPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pass.isEmpty else { return .key }
        return .password
    }

    public static func applyAuthTypeChange(_ type: SSHAuthType, to provider: inout Provider) {
        switch type {
        case .key:
            provider.sshPassword = nil
            let key = provider.sshKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                provider.sshKeyPath = "~/.ssh/id_ed25519"
            }
        case .password:
            provider.sshKeyPath = nil
        }
    }

    public static func normalizeForPersistence(_ provider: Provider, authType: SSHAuthType) -> Provider {
        var copy = provider
        switch authType {
        case .key:
            copy.sshPassword = nil
        case .password:
            copy.sshKeyPath = nil
        }
        return copy
    }
}
