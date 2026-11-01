import Foundation
import Testing
@testable import Kuma

@Suite("Port conflict in-app alert", .serialized)
@MainActor
struct PortConflictAlertTests {

    @Test("portInUse errorDescription uses shared messaging")
    func testPortInUseErrorDescription() {
        let error = ServiceExecutionError.portInUse(
            port: 8080,
            collidingService: "API Gateway",
            startingServiceName: "Worker"
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("8080"))
        #expect(description.contains("API Gateway"))
        #expect(description.contains("Worker"))
        #expect(description.contains("Warn & Prevent Start"))
    }

    @Test("compose port conflict heuristic")
    func testComposePortConflictHeuristic() {
        #expect(PortConflictMessaging.isComposePortConflictMessage("port is already allocated"))
        #expect(PortConflictMessaging.isComposePortConflictMessage("Bind for 0.0.0.0:3000 failed: port is already allocated"))
        #expect(!PortConflictMessaging.isComposePortConflictMessage("network not found"))
    }

    @Test("presenter shows alert for portInUse")
    func testPresenterShowsAlertForPortInUse() {
        let alerts = AlertService.shared
        alerts.dismiss()

        let error = ServiceExecutionError.portInUse(
            port: 3000,
            collidingService: "Other",
            startingServiceName: "Mine"
        )
        ServiceStartFailurePresenter.present(error: error, serviceName: "Mine")

        #expect(alerts.activeAlert?.title == PortConflictMessaging.alertTitle)
        #expect(alerts.activeAlert?.message.contains("3000") == true)
        alerts.dismiss()
    }

    @Test("presenter shows alert for compose failure when policy is warn")
    func testPresenterShowsAlertForComposeFailureUnderWarnPolicy() {
        let suiteName = "test-port-policy-\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suiteName)!
        ud.removePersistentDomain(forName: suiteName)
        ud.set(PortConflictPolicy.warnAndBlock.rawValue, forKey: KumaSettingsKey.portConflictPolicy)

        let alerts = AlertService.shared
        alerts.dismiss()

        let error = ServiceExecutionError.processFailed(
            "Port conflict: another process is already using a host port."
        )
        ServiceStartFailurePresenter.present(error: error, serviceName: "Stack", userDefaults: ud)

        #expect(alerts.activeAlert?.title == PortConflictMessaging.alertTitle)
        alerts.dismiss()
        ud.removePersistentDomain(forName: suiteName)
    }
}
