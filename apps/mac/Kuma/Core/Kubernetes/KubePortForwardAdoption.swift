import Foundation
import os

/// Detect an existing `kubectl port-forward` (e.g. from Terminal) that matches Kuma's planned command.
enum KubePortForwardAdoption {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "KubePortForwardAdoption")

    static func findAdoptablePID(
        plan: KubePortForwardPlan.Built,
        portChecker: LocalPortConflictResolver = .shared
    ) async -> pid_t? {
        guard !plan.localPorts.isEmpty else { return nil }

        var pidSets: [Set<pid_t>] = []
        for port in plan.localPorts {
            let pids = await portChecker.occupyingPIDs(port: port)
            if pids.isEmpty { return nil }
            pidSets.append(Set(pids))
        }

        let common = pidSets.dropFirst().reduce(pidSets[0]) { $0.intersection($1) }
        guard !common.isEmpty else { return nil }

        for pid in common.sorted() {
            guard let command = await processCommandLine(pid: pid) else { continue }
            if matchesPortForward(commandLine: command, plan: plan) {
                logger.info("Adopting kubectl port-forward PID \(pid, privacy: .public)")
                return pid
            }
        }
        return nil
    }

    static func matchesPortForward(commandLine: String, plan: KubePortForwardPlan.Built) -> Bool {
        let lower = commandLine.lowercased()
        guard lower.contains("kubectl"), lower.contains("port-forward") else { return false }
        guard commandLine.contains(plan.kubectlReference) else { return false }

        for arg in plan.arguments where arg.contains(":") && !arg.hasPrefix("-") {
            guard commandLine.contains(arg) else { return false }
        }

        if let ns = value(after: "-n", in: plan.arguments) ?? value(after: "--namespace", in: plan.arguments) {
            guard commandLineContainsFlagValue(commandLine, flags: ["-n", "--namespace"], value: ns) else { return false }
        }

        if let ctx = value(after: "--context", in: plan.arguments) {
            guard commandLineContainsFlagValue(commandLine, flags: ["--context"], value: ctx) else { return false }
        }

        if let kubeconfig = value(after: "--kubeconfig", in: plan.arguments) {
            let expanded = NSString(string: kubeconfig).expandingTildeInPath
            if commandLine.contains(expanded) { return true }
            let base = (expanded as NSString).lastPathComponent
            if !base.isEmpty, commandLine.contains(base) { return true }
            return false
        }

        return true
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func commandLineContainsFlagValue(_ commandLine: String, flags: [String], value: String) -> Bool {
        for flag in flags {
            if commandLine.contains("\(flag) \(value)") { return true }
            if commandLine.contains("\(flag)=\(value)") { return true }
        }
        return commandLine.contains(value)
    }

    private static func processCommandLine(pid: pid_t) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-ww", "-o", "command="]
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            await SubprocessWait.waitForExit(of: process)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return line.isEmpty ? nil : line
        } catch {
            return nil
        }
    }
}
