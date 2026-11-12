import Foundation
import Testing
@testable import Kuma

@Suite("Feature 06 - Category D: Runtime/Process State Integration", .serialized)
@MainActor
struct ServicesRuntimeAndExecutionTests {

    init() async {
        await ProcessTestSupport.resetProcessWorld()
    }

    // MARK: - ServiceStateNotification parsing
    @Test("Runtime.D07: ServiceStateNotification preserves PID when notification omits pid")
    func testServiceStateNotificationPreservesPID() {
        let existing = ServiceExecutionState.running(pid: 4242)
        let userInfo: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.running]
        let parsed = ServiceStateNotification.executionState(from: userInfo, existing: existing)
        #expect(parsed == .running(pid: 4242))
    }

    @Test("Runtime.D09: ServiceStateNotification maps starting and stopping without flattening to idle")
    func testServiceStateNotificationTransientStates() {
        let startingInfo: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.starting]
        #expect(ServiceStateNotification.executionState(from: startingInfo, existing: .idle) == .starting)

        let stoppingInfo: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.stopping]
        #expect(ServiceStateNotification.executionState(from: stoppingInfo, existing: .running(pid: 9)) == .stopping)
    }

    @Test("Runtime.D09b: stray stopped notification ignored while execution is starting")
    func testServiceStateNotificationIgnoresStoppedDuringStarting() {
        let stoppedInfo: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.stopped]
        #expect(ServiceStateNotification.executionState(from: stoppedInfo, existing: .starting) == nil)
        #expect(ServiceStateNotification.executionState(from: stoppedInfo, existing: .idle) == .idle)
    }

    @Test("Runtime.D09c: stopped notification clears stopping to idle after process exit")
    func testServiceStateNotificationStoppedClearsStopping() {
        let stoppedInfo: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.stopped]
        #expect(ServiceStateNotification.executionState(from: stoppedInfo, existing: .stopping) == .idle)
        #expect(ServiceStateNotification.executionState(from: stoppedInfo, existing: .running(pid: 1)) == .idle)
    }

    @Test("Runtime.D09e: stale stopping notification ignored after idle")
    func testStaleStoppingNotificationIgnoredAfterIdle() {
        let stoppingInfo: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.stopping]
        #expect(ServiceStateNotification.executionState(from: stoppingInfo, existing: .idle) == nil)
    }

    @Test("Runtime.D09d: late running notification ignored while execution is stopping")
    func testServiceStateNotificationIgnoresRunningDuringStopping() {
        let runningInfo: [String: Any] = [
            ServiceStateNotification.stateKey: ServiceState.running,
            ServiceStateNotification.pidKey: Int32(99)
        ]
        #expect(ServiceStateNotification.executionState(from: runningInfo, existing: .stopping) == nil)
        #expect(ServiceStateNotification.executionState(from: runningInfo, existing: .idle) == .running(pid: 99))
    }

    @Test("Runtime.D10: ServiceStateStore updates execution state without duplicate writes")
    @MainActor
    func testStoreUpdatesExecutionState() {
        let store = ServiceStateStore()
        let serviceID = UUID()

        store.setExecutionState(.starting, for: serviceID)
        #expect(store.state(for: serviceID) == .starting)

        store.setExecutionState(.starting, for: serviceID)
        #expect(store.state(for: serviceID) == .starting)

        store.setExecutionState(.running(pid: 42), for: serviceID)
        #expect(store.state(for: serviceID) == .running(pid: 42))
    }

    @Test("Runtime.D08: ServiceStateNotification uses exitCode from userInfo")
    func testServiceStateNotificationExitCode() {
        let userInfo: [String: Any] = [
            ServiceStateNotification.stateKey: ServiceState.crashed,
            ServiceStateNotification.exitCodeKey: Int32(42)
        ]
        let parsed = ServiceStateNotification.executionState(from: userInfo, existing: .idle)
        #expect(parsed == .crashed(exitCode: 42))
    }

    // MARK: - [TC-D04] Batch Process Status Lookup
    @Test("Runtime.D04: ProcessRegistry.runningStates returns execution states in single call")
    func testBatchProcessStatusLookup() async {
        let registry = ProcessRegistry.shared
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let states = await registry.runningStates(for: [id1, id2, id3])
        #expect(states.count == 3)
        #expect(states[id1] == .idle)
        #expect(states[id2] == .idle)
        #expect(states[id3] == .idle)
    }

    // MARK: - [TC-D03] ServiceStateStore Batch Refresh
    @Test("Runtime.D03: ServiceStateStore batch refresh integrates with runningStates")
    func testServiceStateStoreBatchRefresh() async {
        let store = ServiceStateStore()
        let id1 = UUID()
        let id2 = UUID()

        await store.refreshProcessStates(for: [id1, id2])
        #expect(store.state(for: id1) == .idle)
        #expect(store.state(for: id2) == .idle)

        store.setExecutionState(.starting, for: id1)
        // Background refresh should not clobber in-flight starting state
        await store.refreshProcessStates(for: [id1])
        #expect(store.state(for: id1) == .starting)
    }

    // MARK: - [TC-D05] ProcessRegistry Launch and Graceful Stop
    @Test("Runtime.D05: ProcessRegistry launches process and stops gracefully")
    func testProcessRegistryLaunchAndGracefulStop() async throws {
        let registry = ProcessRegistry.shared
        let serviceID = UUID()

        // Launch a sleep child process
        let pid = try await registry.launch(
            serviceID: serviceID,
            executable: "/bin/sleep",
            arguments: ["10"]
        )

        #expect(pid > 0)
        let isRunningBefore = await registry.isRunning(serviceID: serviceID)
        #expect(isRunningBefore == true)

        let snapshot = await registry.getSnapshot(serviceID: serviceID)
        #expect(snapshot != nil)
        #expect(snapshot?.pid == pid)

        await registry.stop(serviceID: serviceID)

        let isRunningAfter = await registry.isRunning(serviceID: serviceID)
        #expect(isRunningAfter == false)
        #expect(await registry.getSnapshot(serviceID: serviceID) == nil)
    }

    // MARK: - [TC-D06] ProcessRegistry Output Capture
    @Test("Runtime.D06: ProcessRegistry captures stdout correctly")
    func testProcessRegistryCapturesStdout() async throws {
        let registry = ProcessRegistry.shared
        let serviceID = UUID()

        _ = try await registry.launch(
            serviceID: serviceID,
            executable: "/bin/sh",
            arguments: ["-c", "echo hello-kuma-runtime; sleep 1"]
        )

        var tail = ""
        for _ in 0..<100 {
            tail = RunSpool.tail(for: serviceID) ?? ""
            if tail.contains("hello-kuma-runtime") { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(tail.contains("hello-kuma-runtime"))
        await registry.stop(serviceID: serviceID)
        RunSpool.remove(for: serviceID)
    }

    // MARK: - [TC-D07] Apply Runtime Diff Performance & Version Stability
    @Test("Runtime.D07b: execution state updates without bumping filterVersion when status filters are inactive")
    func testExecutionStateFilterVersionStability() async {
        let store = ServiceStateStore()
        let deckVM = ServicesDeckViewModel(stateStore: store)
        let sID = UUID()

        let initialVersion = deckVM.filterVersion
        store.setExecutionState(.running(pid: 0), for: sID)
        deckVM.notifyExecutionStatesChanged()

        #expect(deckVM.runtime(for: sID).status == .running)
        #expect(deckVM.filterVersion == initialVersion)

        deckVM.selectedStatuses = [.running]
        let versionWithFilter = deckVM.filterVersion
        #expect(versionWithFilter > initialVersion)

        store.setExecutionState(.idle, for: sID)
        deckVM.notifyExecutionStatesChanged()
        #expect(deckVM.filterVersion > versionWithFilter)
    }
}

/// Lets NotificationCenter observers on `.main` run before assertions (CI can defer delivery).
private func drainPostedNotifications() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 5_000_000)
}

private final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withValue<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}
