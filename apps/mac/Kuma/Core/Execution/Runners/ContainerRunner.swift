import Foundation
import os

/// Docker/Podman Compose: detached `up -d` with a stable Compose project name (`-p kuma-<service>`).
public final class ContainerRunner: ServiceRunnerProtocol, @unchecked Sendable {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "ContainerRunner")

    private let processLauncher: any ProcessLaunching
    private let composeCLI: any ComposeCLIExecuting
    private let stateLock = NSLock()
    private var activeStacks: [UUID: ComposeStackContext] = [:]

    public nonisolated init(
        processLauncher: any ProcessLaunching,
        composeCLI: any ComposeCLIExecuting
    ) {
        self.processLauncher = processLauncher
        self.composeCLI = composeCLI
    }

    public func start(
        service: Service,
        provider: Provider
    ) async throws {
        let binaryName = provider.type == .docker ? "docker" : "podman"
        let binaryPath: String?
        if provider.type == .docker {
            binaryPath = await KumaSettingsExecutableResolver.docker()
        } else {
            binaryPath = await KumaSettingsExecutableResolver.podman()
        }
        guard let binaryPath else {
            throw ServiceExecutionError.binaryNotFound(binaryName)
        }

        let context = try ComposeStackResolver.makeContext(service: service, provider: provider, binaryPath: binaryPath)

        if composeCLI is LiveComposeCLI,
           await ComposeStackRuntime.shouldAdoptImplicitDefaultStack(context: context) {
            let adopted = context.adoptingImplicitDefaultProject()
            Self.logger.info(
                "Adopting running compose stack on implicit project for service \(service.id.uuidString, privacy: .public)"
            )
            await LiveLogSystemEmitter.emit(
                serviceID: service.id,
                message: "Adopted running compose stack (project \(adopted.projectName))"
            )
            registerStack(adopted)
            await ExecutionSupervisor.shared.register(
                .composeStack(serviceID: service.id, serviceName: service.name, context: adopted)
            )
            return
        }

        try await runInitialScript(provider: provider, workingDir: context.workingDirectory)

        await LiveLogSystemEmitter.emit(
            serviceID: service.id,
            message: "Running compose up -d (project \(context.projectName))"
        )
        let up = try await composeUpResult(context: context)
        guard up.exitCode == 0 else {
            let failure = composeFailureMessage(
                binaryName: binaryName,
                context: context,
                exitCode: up.exitCode,
                output: up.output
            )
            let oneLine = failure.replacingOccurrences(of: "\n", with: " ")
            await LiveLogSystemEmitter.emit(serviceID: service.id, message: oneLine)
            if PortConflictMessaging.isComposePortConflictMessage(failure),
               PortConflictMessaging.currentPortConflictPolicy() == .warnAndBlock {
                throw ServiceExecutionError.portInUse(
                    port: 0,
                    collidingService: "another process",
                    startingServiceName: service.name
                )
            }
            throw ServiceExecutionError.processFailed(failure)
        }

        guard await composeHasRunningContainers(context: context) else {
            throw ServiceExecutionError.processFailed(
                "Compose up succeeded for project “\(context.projectName)” but no running containers were found. "
                    + "If you already started this stack in Terminal (without `-p \(context.projectName)`), stop it there first or fix port conflicts, then start again from Kuma."
            )
        }

        registerStack(context)
        await ExecutionSupervisor.shared.register(
            .composeStack(serviceID: service.id, serviceName: service.name, context: context)
        )
    }

    public func stop(serviceID: UUID) async {
        await stop(serviceID: serviceID, provider: nil)
    }

    func stop(serviceID: UUID, provider: Provider?) async {
        await processLauncher.stop(serviceID: serviceID)

        let context = await resolveContextForStop(serviceID: serviceID, provider: provider)
        unregisterStack(serviceID: serviceID)

        if let context {
            await teardownStack(context)
        } else {
            Self.logger.warning("No compose context for stop on service \(serviceID)")
        }
    }

    /// Drops in-memory stack tracking without waiting for compose (used after stop timeout).
    func forceUnregister(serviceID: UUID) {
        unregisterStack(serviceID: serviceID)
    }

    /// Short compose down after global stop timeout (best effort).
    func forceComposeTeardown(serviceID: UUID, provider: Provider) async {
        guard let context = await resolveContextForStop(serviceID: serviceID, provider: provider) else { return }
        unregisterStack(serviceID: serviceID)
        await runComposeTeardown(context: context, arguments: context.downArguments, timeout: 15)
        if composeCLI is LiveComposeCLI {
            await teardownDefaultComposeProjectIfNeeded(context)
        }
    }

    public func isRunning(serviceID: UUID) async -> Bool {
        if activeStack(for: serviceID) != nil { return true }
        return await processLauncher.isRunning(serviceID: serviceID)
    }

    // MARK: - Teardown

    private func teardownStack(_ context: ComposeStackContext) async {
        await runComposeTeardown(context: context, arguments: context.downArguments, timeout: KumaExecutionTimeouts.composeDown)

        if composeCLI is LiveComposeCLI, context.projectBinding == .kumaProject {
            await teardownDefaultComposeProjectIfNeeded(context)
        }

        if context.isEphemeralComposeFile {
            let folder = (context.composeFilePath as NSString).deletingLastPathComponent
            try? FileManager.default.removeItem(atPath: folder)
        }
    }

    private func runComposeTeardown(
        context: ComposeStackContext,
        arguments: [String],
        timeout: TimeInterval
    ) async {
        if composeCLI is LiveComposeCLI {
            _ = try? await ComposeCLI.runDetailed(
                context: context,
                arguments: arguments,
                timeout: timeout
            )
        } else {
            _ = try? await composeCLI.run(
                context: context,
                arguments: arguments,
                timeout: timeout
            )
        }
    }

    /// Scripts/Terminal often run `compose up` without Kuma's `-p kuma-…` — tear that down too.
    private func teardownDefaultComposeProjectIfNeeded(_ context: ComposeStackContext) async {
        let listArgs = context.psQuietArgumentsImplicitDefault
        let ps = try? await EphemeralCLI.run(
            executablePath: context.binaryPath,
            arguments: listArgs,
            workingDirectory: context.workingDirectory,
            timeout: 15,
            stdio: .captureSeparated
        )
        let stillRunning = ps?.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(where: { !$0.isEmpty }) ?? false
        guard stillRunning else { return }

        let downArgs = ["compose", "-f", context.composeFilePath, "down", "--timeout", "5", "--remove-orphans"]
        _ = try? await EphemeralCLI.run(
            executablePath: context.binaryPath,
            arguments: downArgs,
            workingDirectory: context.workingDirectory,
            timeout: KumaExecutionTimeouts.composeDown,
            stdio: .discard
        )
    }

    private func resolveContextForStop(serviceID: UUID, provider: Provider?) async -> ComposeStackContext? {
        if let cached = activeStack(for: serviceID) {
            return cached
        }
        guard let provider else { return nil }
        let binaryPath: String?
        if provider.type == .docker {
            binaryPath = await KumaSettingsExecutableResolver.docker()
        } else if provider.type == .podman {
            binaryPath = await KumaSettingsExecutableResolver.podman()
        } else {
            return nil
        }
        guard let binaryPath else { return nil }
        let stub = Service(id: serviceID, name: "stop")
        return try? ComposeStackResolver.makeContext(service: stub, provider: provider, binaryPath: binaryPath)
    }

    // MARK: - Initial script

    private func runInitialScript(
        provider: Provider,
        workingDir: String
    ) async throws {
        if let rawPath = provider.initialScriptPath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else {
                throw ServiceExecutionError.invalidConfiguration("Startup script file not found: \(rawPath)")
            }
            await executeScriptFile(at: expanded, workingDir: workingDir)
            return
        }

        if let initialScript = provider.initialScript?.trimmingCharacters(in: .whitespacesAndNewlines), !initialScript.isEmpty {
            await executeInlineScript(initialScript, workingDir: workingDir)
        }
    }

    private func executeInlineScript(_ script: String, workingDir: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let bootstrap = "[ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; eval \"$1\""
        proc.arguments = ["-c", bootstrap, "--", script]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        await runScriptProcess(proc, timeout: KumaExecutionTimeouts.initialScript)
    }

    private func executeScriptFile(at path: String, workingDir: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [path]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        await runScriptProcess(proc, timeout: KumaExecutionTimeouts.initialScript)
    }

    private func runScriptProcess(
        _ proc: Process,
        timeout: TimeInterval? = nil
    ) async {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            let completed = await SubprocessWait.waitForExit(of: proc, timeout: timeout)
            if let timeout, !completed {
                Self.logger.warning("Initial script timed out after \(Int(timeout))s; continuing with compose.")
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                Self.logger.info("Initial script output: \(output, privacy: .public)")
            }
        } catch {
            Self.logger.warning("Initial script failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Compose health

    private func composeUpResult(
        context: ComposeStackContext
    ) async throws -> ComposeCLI.RunResult {
        if composeCLI is LiveComposeCLI {
            return try await ComposeCLI.runDetailed(
                context: context,
                arguments: context.upArguments,
                timeout: 120
            )
        }
        let exitCode = try await composeCLI.run(
            context: context,
            arguments: context.upArguments,
            timeout: 120
        )
        return ComposeCLI.RunResult(exitCode: exitCode, output: "")
    }

    private func composeHasRunningContainers(context: ComposeStackContext) async -> Bool {
        guard composeCLI is LiveComposeCLI else { return true }
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let ids = await ComposeStackRuntime.runningContainerIDs(
                context: context,
                projectBinding: context.projectBinding
            )
            if !ids.isEmpty { return true }
        }
        return false
    }

    private func composeFailureMessage(
        binaryName: String,
        context: ComposeStackContext,
        exitCode: Int32,
        output: String
    ) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("port is already allocated") || lower.contains("bind for") && lower.contains("failed") {
            return "Port conflict: another process (often an existing `\(binaryName) compose` from Terminal) is already using a host port. Stop that stack or change local ports. \(trimmed)"
        }
        if !trimmed.isEmpty {
            return "\(binaryName) compose up exited with code \(exitCode): \(trimmed)"
        }
        return "\(binaryName) compose up exited with code \(exitCode) (project \(context.projectName))."
    }

    // MARK: - Active stack registry

    private func registerStack(_ context: ComposeStackContext) {
        stateLock.lock()
        defer { stateLock.unlock() }
        activeStacks[context.serviceID] = context
    }

    private func unregisterStack(serviceID: UUID) {
        stateLock.lock()
        defer { stateLock.unlock() }
        activeStacks.removeValue(forKey: serviceID)
    }

    private func activeStack(for serviceID: UUID) -> ComposeStackContext? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeStacks[serviceID]
    }
}

// MARK: - Tests

extension ContainerRunner {
    nonisolated static func expectedUpArguments(composeFile: String, projectName: String) -> [String] {
        [
            "compose", "-p", projectName, "-f", composeFile,
            "up", "-d", "--remove-orphans",
        ]
    }
}
