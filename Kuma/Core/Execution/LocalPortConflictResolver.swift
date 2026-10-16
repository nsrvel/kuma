import Foundation
import os

/// Applies user port-conflict policy before binding local ports (kubectl / SSH port-forward).
public final class LocalPortConflictResolver: Sendable {
    public static let shared = LocalPortConflictResolver()

    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "LocalPortConflictResolver")

    private let processRegistry: ProcessRegistry

    public init(processRegistry: ProcessRegistry = .shared) {
        self.processRegistry = processRegistry
    }

    public func occupyingPIDs(port: Int) async -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-ti", ":\(port)"]
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        process.standardOutput = pipe

        do {
            try process.run()
            await SubprocessWait.waitForExit(of: process)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty else {
                return []
            }
            let currentPID = ProcessInfo.processInfo.processIdentifier
            return output
                .components(separatedBy: .newlines)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { $0 != currentPID }
        } catch {
            Self.logger.debug("lsof check for port \(port) exited: \(error.localizedDescription)")
            return []
        }
    }

    public func ensurePortAvailable(
        port: Int,
        startingServiceID: UUID,
        startingServiceName: String
    ) async throws {
        let rawPolicy = UserDefaults.standard.string(forKey: KumaSettingsKey.portConflictPolicy)
            ?? PortConflictPolicy.warnAndBlock.rawValue
        let policy = PortConflictPolicy(rawValue: rawPolicy) ?? .warnAndBlock

        let pids = await occupyingPIDs(port: port)
        guard !pids.isEmpty else { return }

        switch policy {
        case .killExisting:
            for pid in pids {
                Self.logger.info("Port \(port) was held by PID \(pid); sending SIGTERM")
                kill(pid, SIGTERM)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)

        case .warnAndBlock:
            let foreignPIDs = await foreignOccupants(pids: pids, excludingServiceID: startingServiceID)
            guard !foreignPIDs.isEmpty else { return }

            let collidingLabel = await collidingServiceLabel(forPID: foreignPIDs[0])
            await SystemNotificationCenter.shared.send(.portCollision(port: port, collidingService: collidingLabel))
            throw ServiceExecutionError.portInUse(
                port: port,
                collidingService: collidingLabel,
                startingServiceName: startingServiceName
            )
        }
    }

    private func foreignOccupants(pids: [Int32], excludingServiceID: UUID) async -> [Int32] {
        var foreign: [Int32] = []
        for pid in pids {
            if let ownerID = await processRegistry.serviceID(forPID: pid), ownerID == excludingServiceID {
                continue
            }
            foreign.append(pid)
        }
        return foreign
    }

    private func collidingServiceLabel(forPID pid: Int32) async -> String {
        if let name = await processRegistry.serviceName(forPID: pid) {
            return name
        }
        return "PID \(pid)"
    }
}
