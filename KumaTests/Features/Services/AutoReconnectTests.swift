import Foundation
import Testing
@testable import Kuma

@MainActor
struct AutoReconnectTests {
    @Test("AutoReconnect: policy caps at three attempts with backoff")
    func testAutoReconnectPolicy() {
        #expect(AutoReconnectPolicy.maxAttempts == 3)
        #expect(AutoReconnectPolicy.backoffNanoseconds(attempt: 1) == 2_000_000_000)
        #expect(AutoReconnectPolicy.backoffNanoseconds(attempt: 2) == 5_000_000_000)
        #expect(AutoReconnectPolicy.backoffNanoseconds(attempt: 3) == 10_000_000_000)
    }

    @Test("AutoReconnect: execution record maps reconnecting attempt counts")
    func testExecutionRecordReconnectingState() {
        let record = ExecutionRecord(
            serviceID: UUID(),
            serviceName: "api",
            mode: .managedProcess,
            serviceState: .reconnecting,
            reconnectAttempt: 2,
            reconnectMax: 3
        )
        #expect(record.executionState == .reconnecting(attempt: 2, maxAttempts: 3))
    }

    @Test("AutoReconnect: provider flag respects supported categories")
    func testProviderAutoReconnectEligibility() {
        let kube = Provider(serviceID: UUID(), type: .kubernetes, autoReconnect: true)
        #expect(kube.isAutoReconnectEnabled)

        let kubeOff = Provider(serviceID: UUID(), type: .kubernetes, autoReconnect: false)
        #expect(!kubeOff.isAutoReconnectEnabled)

        let docker = Provider(serviceID: UUID(), type: .docker, autoReconnect: true)
        #expect(!docker.isAutoReconnectEnabled)
    }

    @Test("Runtime.D09c: ServiceStateNotification maps reconnecting")
    func testServiceStateNotificationReconnecting() {
        let info: [String: Any] = [ServiceStateNotification.stateKey: ServiceState.reconnecting]
        #expect(
            ServiceStateNotification.executionState(from: info, existing: .idle)
                == .reconnecting(attempt: 1, maxAttempts: AutoReconnectPolicy.maxAttempts)
        )
    }

    @Test("AutoReconnect: supervisor snapshot rules during reconnect")
    func testSupervisorSnapshotReconnectTransitions() {
        let reconnecting = ServiceExecutionState.reconnecting(attempt: 1, maxAttempts: 3)
        #expect(
            !ServiceStateStore.shouldIgnoreSupervisorTransitionDuringReconnect(
                from: reconnecting,
                to: .running(pid: 42)
            )
        )
        #expect(
            !ServiceStateStore.shouldIgnoreSupervisorTransitionDuringReconnect(
                from: reconnecting,
                to: .reconnecting(attempt: 2, maxAttempts: 3)
            )
        )
        #expect(
            !ServiceStateStore.shouldIgnoreSupervisorTransitionDuringReconnect(
                from: reconnecting,
                to: .crashed(exitCode: 1)
            )
        )
        #expect(
            ServiceStateStore.shouldIgnoreSupervisorTransitionDuringReconnect(
                from: reconnecting,
                to: .idle
            )
        )
        #expect(
            ServiceStateStore.shouldIgnoreSupervisorTransitionDuringReconnect(
                from: reconnecting,
                to: .starting
            )
        )
        #expect(
            !ServiceStateStore.shouldIgnoreSupervisorTransitionDuringReconnect(
                from: .running(pid: 1),
                to: .idle
            )
        )
    }
}

@Suite("Auto reconnect workload", .serialized)
struct AutoReconnectWorkloadTests {

    init() async {
        await ProcessTestSupport.resetProcessWorld()
    }

    @Test("AutoReconnect: hasActiveWorkload false while reconnecting without process")
    func testHasActiveWorkloadDuringReconnect() async {
        let serviceID = UUID()
        await ExecutionSupervisor.shared.setManagedProcessReconnecting(
            serviceID: serviceID,
            serviceName: "Test",
            attempt: 1,
            maxAttempts: AutoReconnectPolicy.maxAttempts
        )
        #expect(await ExecutionSupervisor.shared.hasActiveWorkload(serviceID: serviceID) == false)
        #expect(await ExecutionSupervisor.shared.isOperational(serviceID: serviceID) == true)
        await ExecutionSupervisor.shared.cancelReconnect(serviceID: serviceID)
        await ExecutionSupervisor.shared.unregister(serviceID: serviceID)
    }
}
