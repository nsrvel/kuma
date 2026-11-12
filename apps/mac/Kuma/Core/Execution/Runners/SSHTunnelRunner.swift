import Foundation
import os

/// Runner responsible for secure remote SSH tunneling and port-forwarding.
public final class SSHTunnelRunner: ServiceRunnerProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "SSHTunnelRunner")

    private let processLauncher: any ProcessLaunching
    private let serviceRepository: any ServiceRepositoryProtocol

    private let stateLock = NSLock()
    private var activeAskpassScripts: [UUID: String] = [:]

    public nonisolated init(
        processLauncher: any ProcessLaunching,
        serviceRepository: any ServiceRepositoryProtocol = ServiceRepository()
    ) {
        self.processLauncher = processLauncher
        self.serviceRepository = serviceRepository
    }

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        guard let host = provider.sshHost?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("SSH Host is not configured.")
        }

        let user = provider.sshUser?.trimmingCharacters(in: .whitespacesAndNewlines) ?? NSUserName()
        let port = provider.sshPort ?? 22
        let portMappings = try await serviceRepository.fetchPortMappings(forService: service.id)

        if portMappings.isEmpty {
            throw ServiceExecutionError.invalidConfiguration("At least one port mapping (Local:Remote) is required for SSH tunneling.")
        }

        var args = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-p", "\(port)"
        ]

        var env: [String: String]? = nil

        // Decrypt SSH password or setup SSH Key
        var decryptedPassword = provider.sshPassword?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawPass = decryptedPassword, !rawPass.isEmpty {
            if rawPass.starts(with: "vault:") {
                decryptedPassword = try? CryptoVault.shared.decrypt(cipherText: rawPass)
            }
        }

        if let pass = decryptedPassword, !pass.isEmpty {
            // Setup ephemeral SSH_ASKPASS script
            let askpassScript = try createAskpassScript(password: pass, serviceID: service.id)
            registerAskpass(askpassScript, for: service.id)

            env = [
                "SSH_ASKPASS": askpassScript,
                "SSH_ASKPASS_REQUIRE": "force",
                "DISPLAY": "kuma:0"
            ]
            args.append(contentsOf: [
                "-o", "PreferredAuthentications=password,keyboard-interactive",
                "-o", "PubkeyAuthentication=no",
                "-o", "NumberOfPasswordPrompts=1"
            ])
        } else if var keyPath = provider.sshKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines), !keyPath.isEmpty {
            // Decrypt SSH key path if encrypted in vault
            if keyPath.starts(with: "vault:") {
                do {
                    keyPath = try CryptoVault.shared.decrypt(cipherText: keyPath)
                } catch {
                    throw ServiceExecutionError.processFailed("Failed to decrypt SSH key path: \(error.localizedDescription)")
                }
            }
            let expandedKey = NSString(string: keyPath).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: expandedKey) {
                throw ServiceExecutionError.invalidConfiguration("SSH private key file not found: '\(keyPath)'")
            }
            args.append(contentsOf: ["-i", expandedKey])
        }

        // Port forwarding arguments
        for mapping in portMappings {
            args.append(contentsOf: ["-L", "\(mapping.localPort):localhost:\(mapping.remotePort)"])
        }

        args.append("\(user)@\(host)")

        for mapping in portMappings {
            try await LocalPortConflictResolver.shared.ensurePortAvailable(
                port: mapping.localPort,
                startingServiceID: service.id,
                startingServiceName: service.name
            )
        }

        _ = try await processLauncher.launch(
            serviceID: service.id,
            serviceName: service.name,
            executable: "/usr/bin/ssh",
            arguments: args,
            workingDirectory: nil,
            environment: env,
            onOutput: nil
        )
    }

    public func stop(serviceID: UUID) async {
        await processLauncher.stop(serviceID: serviceID)
        cleanupAskpass(for: serviceID)
    }

    public func isRunning(serviceID: UUID) async -> Bool {
        await processLauncher.isRunning(serviceID: serviceID)
    }

    private func createAskpassScript(password: String, serviceID: UUID) throws -> String {
        let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("kuma-ssh-\(serviceID.uuidString)")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let scriptPath = (tempDir as NSString).appendingPathComponent("askpass.sh")
        let escapedPassword = password.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")

        let scriptContent = """
        #!/bin/sh
        cat << 'EOF'
        \(escapedPassword)
        EOF
        """
        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
        return scriptPath
    }

    private func registerAskpass(_ path: String, for serviceID: UUID) {
        stateLock.lock()
        defer { stateLock.unlock() }
        activeAskpassScripts[serviceID] = path
    }

    private func cleanupAskpass(for serviceID: UUID) {
        stateLock.lock()
        let path = activeAskpassScripts.removeValue(forKey: serviceID)
        stateLock.unlock()

        if let path {
            let folder = (path as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: folder)
        }
    }

}
