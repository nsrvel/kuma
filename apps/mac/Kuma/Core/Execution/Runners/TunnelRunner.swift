import Foundation
import os

/// Runner responsible for public tunneling via Cloudflare Tunnel (`cloudflared`) or Ngrok.
public final class TunnelRunner: ServiceRunnerProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "TunnelRunner")

    private let processRegistry: ProcessRegistry

    public nonisolated init(processRegistry: ProcessRegistry = .shared) {
        self.processRegistry = processRegistry
    }

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        let engine = provider.tunnelType?.lowercased() ?? "cloudflare"

        guard let rawTarget = provider.tunnelTargetUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTarget.isEmpty else {
            throw ServiceExecutionError.invalidConfiguration("Tunnel target (port or local URL) is required.")
        }

        let normalizedTarget = URLNormalizer.normalize(rawTarget, defaultToHttps: false) ?? "http://localhost:3000"

        if engine == "ngrok" {
            try await startNgrok(service: service, provider: provider, target: normalizedTarget)
        } else {
            try await startCloudflare(service: service, provider: provider, target: normalizedTarget)
        }
    }

    public func stop(serviceID: UUID) async {
        await processRegistry.stop(serviceID: serviceID)
    }

    public func isRunning(serviceID: UUID) async -> Bool {
        await processRegistry.isRunning(serviceID: serviceID)
    }

    // MARK: - Cloudflare Tunnel

    private func startCloudflare(
        service: Service,
        provider: Provider,
        target: String
    ) async throws {
        guard let binaryPath = await KumaSettingsExecutableResolver.cloudflared() else {
            throw ServiceExecutionError.binaryNotFound("cloudflared")
        }

        let args = ["tunnel", "--url", target, "--no-autoupdate"]

        _ = try await processRegistry.launch(
            serviceID: service.id,
            serviceName: service.name,
            executable: binaryPath,
            arguments: args,
            onOutput: nil
        )
    }

    // MARK: - Ngrok Tunnel

    private func startNgrok(
        service: Service,
        provider: Provider,
        target: String
    ) async throws {
        guard let binaryPath = await KumaSettingsExecutableResolver.ngrok() else {
            throw ServiceExecutionError.binaryNotFound("ngrok")
        }

        var args = ["http", target]

        if var token = provider.ngrokAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            if token.starts(with: "vault:") {
                token = (try? CryptoVault.shared.decrypt(cipherText: token)) ?? token
            }
            args.append(contentsOf: ["--authtoken", token])
        }

        _ = try await processRegistry.launch(
            serviceID: service.id,
            serviceName: service.name,
            executable: binaryPath,
            arguments: args,
            onOutput: nil
        )
    }
}
