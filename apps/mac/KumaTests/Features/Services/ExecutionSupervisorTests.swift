import Foundation
import Testing
@testable import Kuma

@Suite("Execution supervisor", .serialized)
struct ExecutionSupervisorTests {

    init() async {
        await ProcessTestSupport.resetProcessWorld()
    }

    @Test("Managed process crash sets lastFailure from spool tail")
    func testManagedExitLastFailure() async throws {
        let serviceID = UUID()
        let spoolURL = RunSpool.url(for: serviceID)
        try "fatal: connection refused\n".write(to: spoolURL, atomically: true, encoding: .utf8)

        await ExecutionSupervisor.shared.register(
            .managedProcess(serviceID: serviceID, serviceName: "Test", pid: 42, startedAt: Date())
        )
        await ExecutionSupervisor.shared.handleManagedProcessExit(
            serviceID: serviceID,
            serviceName: "Test",
            exitCode: 1,
            intentionalStop: false
        )

        let failure = await ExecutionSupervisor.shared.lastFailure(for: serviceID)
        #expect(failure?.contains("connection refused") == true)
        await ExecutionSupervisor.shared.unregister(serviceID: serviceID)
    }

    @Test("Poller supervisor helpers parse ps output")
    func testBatchProcessLookup() async throws {
        let serviceID = UUID()
        let pid = try await ProcessRegistry.shared.launch(
            serviceID: serviceID,
            executable: "/bin/sleep",
            arguments: ["5"]
        )
        let index = await PollerSupervisorHelpers.batchProcessLookup()
        let matchedByPID = index.values.contains(pid)
        let matchedByCommand = index.keys.contains(where: { $0.contains("sleep") })
        #expect(matchedByPID || matchedByCommand)
        await ProcessRegistry.shared.stop(serviceID: serviceID)
    }
}
