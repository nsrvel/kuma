import Foundation
import os

/// Coalesced execution truth for all services (managed processes, compose stacks, pollers).
public actor ExecutionSupervisor {
    public static let shared = ExecutionSupervisor()
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "ExecutionSupervisor")

    private var records: [UUID: ExecutionRecord] = [:]
    private var composeContexts: [UUID: ComposeStackContext] = [:]
    private var pollerJobs: [UUID: PollerJob] = [:]

    private var snapshotContinuations: [UUID: AsyncStream<[UUID: ExecutionRecord]>.Continuation] = [:]
    private var publishTask: Task<Void, Never>?
    private var composeLoopTask: Task<Void, Never>?
    private var pollerLoopTask: Task<Void, Never>?

    private let stopGate = ServiceStopGate()

    private struct ReconnectSession {
        var reconnectAttemptsCompleted: Int = 0
        var task: Task<Void, Never>?
    }

    private static let reconnectLogger = Logger(subsystem: "lokastudio.kuma", category: "AutoReconnect")
    private var reconnectSessions: [UUID: ReconnectSession] = [:]
    private var lastLoggedHealthState: [UUID: ServiceState] = [:]
    private var lastLoggedProcessRunning: [UUID: Bool] = [:]

    private init() {}

    // MARK: - Public stream

    public func snapshotStream() -> AsyncStream<[UUID: ExecutionRecord]> {
        let id = UUID()
        return AsyncStream { continuation in
            snapshotContinuations[id] = continuation
            continuation.yield(records)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        snapshotContinuations.removeValue(forKey: id)
    }

    public func record(for serviceID: UUID) -> ExecutionRecord? {
        records[serviceID]
    }

    public func lastFailure(for serviceID: UUID) -> String? {
        records[serviceID]?.lastFailure
    }

    public func states(for serviceIDs: [UUID]) -> [UUID: ServiceExecutionState] {
        var out: [UUID: ServiceExecutionState] = [:]
        for id in serviceIDs {
            out[id] = records[id]?.executionState ?? .idle
        }
        return out
    }

    public func isOperational(serviceID: UUID) async -> Bool {
        if let state = records[serviceID]?.serviceState,
           state == .running || state == .starting || state == .reconnecting {
            return true
        }
        return await ProcessRegistry.shared.isRunning(serviceID: serviceID)
    }

    public func runningServiceIDs(among candidates: Set<UUID>) async -> Set<UUID> {
        var running: Set<UUID> = []
        for id in candidates {
            let state = records[id]?.serviceState
            if state == .running || state == .starting || state == .reconnecting {
                running.insert(id)
            }
        }
        let processIDs = Set(await ProcessRegistry.shared.activeRunningServiceIDs())
        running.formUnion(processIDs.intersection(candidates))
        return running
    }

    // MARK: - Register handles

    public func register(_ handle: ExecutionHandle) {
        switch handle {
        case .managedProcess(let serviceID, let serviceName, let pid, let startedAt):
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: serviceName,
                mode: .managedProcess,
                serviceState: .running,
                pid: pid,
                startedAt: startedAt
            )
        case .composeStack(let serviceID, let serviceName, let context):
            composeContexts[serviceID] = context
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: serviceName,
                mode: .composeStack,
                serviceState: .running,
                startedAt: Date()
            )
            ensureComposeLoop()
        case .pollerHealth(let serviceID, let serviceName, let url, let interval):
            pollerJobs[serviceID] = .health(url: url, interval: interval, serviceName: serviceName)
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: serviceName,
                mode: .poller,
                serviceState: .running,
                startedAt: Date()
            )
            ensurePollerLoop()
        case .pollerProcess(let serviceID, let serviceName, let processName, let interval):
            pollerJobs[serviceID] = .process(name: processName, interval: interval, serviceName: serviceName)
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: serviceName,
                mode: .poller,
                serviceState: .running,
                startedAt: Date()
            )
            ensurePollerLoop()
        }
        schedulePublish()
    }

    public func unregister(serviceID: UUID, serviceState: ServiceState = .stopped) {
        composeContexts.removeValue(forKey: serviceID)
        pollerJobs.removeValue(forKey: serviceID)
        pollerDue.removeValue(forKey: serviceID)
        lastLoggedHealthState.removeValue(forKey: serviceID)
        lastLoggedProcessRunning.removeValue(forKey: serviceID)
        if let rec = records[serviceID] {
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: rec.serviceName,
                mode: rec.mode,
                serviceState: serviceState,
                startedAt: rec.startedAt,
                lastFailure: rec.lastFailure
            )
        } else {
            records.removeValue(forKey: serviceID)
        }
        if composeContexts.isEmpty { composeLoopTask?.cancel(); composeLoopTask = nil }
        if pollerJobs.isEmpty { pollerLoopTask?.cancel(); pollerLoopTask = nil }
        schedulePublish()
    }

    public func handleManagedProcessExit(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32,
        intentionalStop: Bool
    ) async {
        let failureTail = (!intentionalStop && exitCode != 0) ? RunSpool.tail(for: serviceID) : nil
        RunSpool.remove(for: serviceID)
        KubeLiveTargetDisplay.clear(serviceID: serviceID)

        if intentionalStop {
            await LiveLogSystemEmitter.emit(serviceID: serviceID, message: "Stopped (exit \(exitCode)).")
            cancelReconnect(serviceID: serviceID)
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: serviceName,
                mode: .managedProcess,
                serviceState: .stopped,
                exitCode: nil,
                startedAt: records[serviceID]?.startedAt,
                lastFailure: nil
            )
            schedulePublish()
            await LiveLogSystemEmitter.endCapture(serviceID: serviceID)
            return
        }

        let tookReconnect = await handleAutoReconnectIfNeeded(
            serviceID: serviceID,
            serviceName: serviceName,
            exitCode: exitCode
        )
        if tookReconnect { return }

        if exitCode == 0 {
            await LiveLogSystemEmitter.emit(serviceID: serviceID, message: "Stopped (exit 0).")
            records[serviceID] = ExecutionRecord(
                serviceID: serviceID,
                serviceName: serviceName,
                mode: .managedProcess,
                serviceState: .stopped,
                exitCode: nil,
                startedAt: records[serviceID]?.startedAt,
                lastFailure: nil
            )
            schedulePublish()
            await LiveLogSystemEmitter.endCapture(serviceID: serviceID)
            return
        }

        await emitCrashLiveLogLines(serviceID: serviceID, exitCode: exitCode, detail: failureTail)
        await finalizeManagedProcessCrash(
            serviceID: serviceID,
            serviceName: serviceName,
            exitCode: exitCode,
            failure: failureTail,
            notify: true
        )
        await LiveLogSystemEmitter.endCapture(serviceID: serviceID)
    }

    public func setManagedProcessReconnecting(
        serviceID: UUID,
        serviceName: String,
        attempt: Int,
        maxAttempts: Int
    ) {
        records[serviceID] = ExecutionRecord(
            serviceID: serviceID,
            serviceName: serviceName,
            mode: .managedProcess,
            serviceState: .reconnecting,
            startedAt: records[serviceID]?.startedAt,
            reconnectAttempt: attempt,
            reconnectMax: maxAttempts
        )
        schedulePublish()
        Task {
            await LiveLogSystemEmitter.emit(
                serviceID: serviceID,
                message: "Reconnecting (attempt \(attempt)/\(maxAttempts))…"
            )
        }
    }

    public func finalizeManagedProcessCrash(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32,
        failure: String?,
        notify: Bool
    ) async {
        records[serviceID] = ExecutionRecord(
            serviceID: serviceID,
            serviceName: serviceName,
            mode: .managedProcess,
            serviceState: .crashed,
            exitCode: exitCode == 0 ? 1 : exitCode,
            startedAt: records[serviceID]?.startedAt,
            lastFailure: failure
        )
        schedulePublish()

        guard notify,
              KumaSettingsKey.bool(
                  forKey: KumaSettingsKey.notifyOnServiceFailure,
                  defaultValue: true,
                  fallbackKey: KumaSettingsKey.legacyNotifyOnCrash
              ) else { return }

        await SystemNotificationCenter.shared.send(
            .serviceCrash(
                serviceName: serviceName,
                reason: failure ?? "Exited with code \(exitCode)"
            )
        )
    }

    public func stop(serviceID: UUID) async {
        await stopGate.runOnce(serviceID: serviceID) {
            await self.performStop(serviceID: serviceID)
        }
    }

    public func stopAll() async {
        for id in Array(records.keys) {
            await performStop(serviceID: id)
        }
        await ProcessRegistry.shared.terminateAllAsync()
        records.removeAll()
        composeContexts.removeAll()
        pollerJobs.removeAll()
        composeLoopTask?.cancel()
        pollerLoopTask?.cancel()
        schedulePublish()
    }

    private func performStop(serviceID: UUID) async {
        await LiveLogSystemEmitter.emit(serviceID: serviceID, message: "Stopping service…")
        cancelReconnect(serviceID: serviceID)
        if await ProcessRegistry.shared.isRunning(serviceID: serviceID) {
            await ProcessRegistry.shared.stop(serviceID: serviceID)
        }
        composeContexts.removeValue(forKey: serviceID)
        pollerJobs.removeValue(forKey: serviceID)
        unregister(serviceID: serviceID, serviceState: .stopped)
        await LiveLogSystemEmitter.endCapture(serviceID: serviceID)
    }

    // MARK: - Coalesced publish

    private func schedulePublish() {
        publishTask?.cancel()
        publishTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let snap = records
            for continuation in snapshotContinuations.values {
                continuation.yield(snap)
            }
        }
    }

    // MARK: - Compose batch loop

    private func ensureComposeLoop() {
        guard composeLoopTask == nil else { return }
        composeLoopTask = Task {
            while !Task.isCancelled {
                await pollComposeStacks()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func pollComposeStacks() async {
        guard !composeContexts.isEmpty else { return }
        for (serviceID, context) in composeContexts {
            let running = await composeHasRunningContainers(context: context)
            if !running {
                let name = records[serviceID]?.serviceName ?? "Service"
                await LiveLogSystemEmitter.emit(
                    serviceID: serviceID,
                    message: "Compose stack has no running containers"
                )
                records[serviceID] = ExecutionRecord(
                    serviceID: serviceID,
                    serviceName: name,
                    mode: .composeStack,
                    serviceState: .crashed,
                    exitCode: 1,
                    startedAt: records[serviceID]?.startedAt,
                    lastFailure: "Compose stack no longer has running containers"
                )
                composeContexts.removeValue(forKey: serviceID)
                await LiveLogSystemEmitter.endCapture(serviceID: serviceID)
            }
        }
        schedulePublish()
    }

    private func composeHasRunningContainers(context: ComposeStackContext) async -> Bool {
        let ids = await ComposeStackRuntime.runningContainerIDs(
            context: context,
            projectBinding: context.projectBinding
        )
        return !ids.isEmpty
    }

    // MARK: - Poller loop

    private enum PollerJob {
        case health(url: URL, interval: Int, serviceName: String)
        case process(name: String, interval: Int, serviceName: String)
    }

    private struct PollerDue {
        var nextDue: Date
        var job: PollerJob
    }

    private var pollerDue: [UUID: PollerDue] = [:]

    private func ensurePollerLoop() {
        let now = Date()
        for (id, job) in pollerJobs {
            let interval: Int
            switch job {
            case .health(_, let i, _), .process(_, let i, _): interval = i
            }
            if pollerDue[id] == nil {
                pollerDue[id] = PollerDue(nextDue: now, job: job)
            }
        }
        guard pollerLoopTask == nil else { return }
        pollerLoopTask = Task {
            while !Task.isCancelled {
                await runPollerTick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func runPollerTick() async {
        guard !pollerDue.isEmpty else { return }
        let now = Date()
        var processNames: [String] = []
        for (_, due) in pollerDue {
            if case .process(let name, _, _) = due.job {
                processNames.append(name)
            }
        }
        let psIndex = await PollerSupervisorHelpers.batchProcessLookup()

        for (serviceID, due) in pollerDue where due.nextDue <= now {
            switch due.job {
            case .health(let url, let interval, let serviceName):
                await pollHealth(serviceID: serviceID, serviceName: serviceName, url: url, interval: interval)
            case .process(let name, let interval, let serviceName):
                await pollProcess(serviceID: serviceID, serviceName: serviceName, name: name, interval: interval, psIndex: psIndex)
            }
        }
    }

    private func pollHealth(serviceID: UUID, serviceName: String, url: URL, interval: Int) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        let serviceState: ServiceState
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) {
                serviceState = .running
            } else {
                serviceState = .crashed
            }
        } catch {
            serviceState = .crashed
        }
        records[serviceID] = ExecutionRecord(
            serviceID: serviceID,
            serviceName: serviceName,
            mode: .poller,
            serviceState: serviceState,
            exitCode: serviceState == .crashed ? 1 : nil,
            startedAt: records[serviceID]?.startedAt,
            lastFailure: serviceState == .crashed ? "Health check failed" : nil
        )
        pollerDue[serviceID]?.nextDue = Date().addingTimeInterval(TimeInterval(interval))
        schedulePublish()
        let previous = lastLoggedHealthState[serviceID]
        if previous != serviceState {
            lastLoggedHealthState[serviceID] = serviceState
            await LiveLogSystemEmitter.emitRawLine(
                serviceID: serviceID,
                message: "[HEALTH] \(url.absoluteString) -> \(serviceState)"
            )
        }
    }

    private func pollProcess(serviceID: UUID, serviceName: String, name: String, interval: Int, psIndex: [String: pid_t]) async {
        let pid = psIndex.first { $0.key.contains(name) }?.value
        let isRunning = pid != nil
        let previous = lastLoggedProcessRunning[serviceID]
        records[serviceID] = ExecutionRecord(
            serviceID: serviceID,
            serviceName: serviceName,
            mode: .poller,
            serviceState: pid != nil ? .running : .stopped,
            pid: pid,
            startedAt: records[serviceID]?.startedAt
        )
        pollerDue[serviceID]?.nextDue = Date().addingTimeInterval(TimeInterval(interval))
        schedulePublish()
        if previous != isRunning {
            lastLoggedProcessRunning[serviceID] = isRunning
            let detail = pid.map { "PID \($0)" } ?? "not running"
            await LiveLogSystemEmitter.emitRawLine(
                serviceID: serviceID,
                message: "[MONITOR] \(name) -> \(detail)"
            )
        }
    }

    // MARK: - Auto reconnect

    func beginReconnectSession(serviceID: UUID) {
        reconnectSessions[serviceID]?.task?.cancel()
        reconnectSessions[serviceID] = ReconnectSession(reconnectAttemptsCompleted: 0, task: nil)
    }

    func cancelReconnect(serviceID: UUID) {
        reconnectSessions[serviceID]?.task?.cancel()
        reconnectSessions.removeValue(forKey: serviceID)
    }

    func resetReconnectForTests() {
        for id in Array(reconnectSessions.keys) {
            cancelReconnect(serviceID: id)
        }
    }

    /// Returns true when reconnect handling took over (no immediate terminal crash UI).
    func handleAutoReconnectIfNeeded(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32
    ) async -> Bool {
        guard let provider = await ServiceExecutionEngine.shared.activeProvider(for: serviceID) else { return false }
        guard provider.isAutoReconnectEnabled else { return false }

        var session = reconnectSessions[serviceID] ?? ReconnectSession()
        if session.reconnectAttemptsCompleted >= AutoReconnectPolicy.maxAttempts {
            await finishReconnectExhausted(
                serviceID: serviceID,
                serviceName: serviceName,
                exitCode: exitCode,
                session: &session
            )
            return true
        }

        session.reconnectAttemptsCompleted += 1
        let attempt = session.reconnectAttemptsCompleted
        reconnectSessions[serviceID] = session

        setManagedProcessReconnecting(
            serviceID: serviceID,
            serviceName: serviceName,
            attempt: attempt,
            maxAttempts: AutoReconnectPolicy.maxAttempts
        )

        session.task?.cancel()
        session.task = Task {
            let delay = AutoReconnectPolicy.backoffNanoseconds(attempt: attempt)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            do {
                try await ServiceExecutionEngine.shared.start(serviceID: serviceID)
            } catch {
                Self.reconnectLogger.warning(
                    "Auto reconnect attempt \(attempt, privacy: .public) failed for \(serviceName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                await LiveLogSystemEmitter.emit(
                    serviceID: serviceID,
                    message: "Reconnect attempt \(attempt) failed: \(error.localizedDescription)"
                )
                _ = await ExecutionSupervisor.shared.handleAutoReconnectIfNeeded(
                    serviceID: serviceID,
                    serviceName: serviceName,
                    exitCode: exitCode
                )
            }
        }
        reconnectSessions[serviceID] = session
        return true
    }

    private func finishReconnectExhausted(
        serviceID: UUID,
        serviceName: String,
        exitCode: Int32,
        session: inout ReconnectSession
    ) async {
        session.task?.cancel()
        reconnectSessions.removeValue(forKey: serviceID)
        let message = "Auto reconnect failed after \(AutoReconnectPolicy.maxAttempts) attempts"
        await LiveLogSystemEmitter.emit(serviceID: serviceID, message: "Auto reconnect exhausted")
        await emitCrashLiveLogLines(serviceID: serviceID, exitCode: exitCode, detail: message)
        await finalizeManagedProcessCrash(
            serviceID: serviceID,
            serviceName: serviceName,
            exitCode: exitCode,
            failure: message,
            notify: true
        )
        await LiveLogSystemEmitter.endCapture(serviceID: serviceID)
    }

    private func emitCrashLiveLogLines(serviceID: UUID, exitCode: Int32, detail: String?) async {
        var messages = ["Crashed (exit \(exitCode))."]
        if let detail, !detail.isEmpty {
            for line in detail.split(separator: "\n", omittingEmptySubsequences: true) {
                messages.append(String(line))
            }
        }
        await LiveLogSystemEmitter.emitBatch(serviceID: serviceID, messages: messages)
    }
}

enum PollerSupervisorHelpers {
    static func batchProcessLookup() async -> [String: pid_t] {
        guard let result = try? await EphemeralCLI.run(
            executablePath: "/bin/ps",
            arguments: ["-axo", "pid=,command="],
            workingDirectory: nil,
            timeout: KumaExecutionTimeouts.kubectlSubcommand,
            stdio: .captureSeparated
        ) else {
            return [:]
        }
        var map: [String: pid_t] = [:]
        for line in result.stdout.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            let pidStr = trimmed[..<space].trimmingCharacters(in: .whitespaces)
            let cmd = trimmed[space...].trimmingCharacters(in: .whitespaces)
            guard let pid = pid_t(pidStr) else { continue }
            map[cmd] = pid
        }
        return map
    }
}
