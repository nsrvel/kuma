import Foundation
import Testing
import SwiftUI
@testable import Kuma

@Suite("Feature 00 - Category D: Alert Bus, Actions, Isolation & Single-Slot Modal")
@MainActor
struct AlertServiceTests {

    // MARK: - [TC-D01] Initial State
    @Test("TC-D01: AlertService activeAlert is nil upon initialization or reset")
    func testInitialAlertStateNil() {
        let service = AlertService.shared
        service.dismiss()
        #expect(service.activeAlert == nil)
    }

    // MARK: - [TC-D02] Present Alert Sets Payload
    @Test("TC-D02: show assigns all properties to activeAlert")
    func testPresentAlertSetsPayload() {
        let service = AlertService.shared
        defer { service.dismiss() }

        service.show(
            title: "Delete Service?",
            message: "This will permanently delete the service.",
            primaryButton: .destructive(title: "Delete", action: {}),
            secondaryButton: .cancel(title: "Cancel")
        )

        #expect(service.activeAlert != nil)
        #expect(service.activeAlert?.title == "Delete Service?")
        #expect(service.activeAlert?.message == "This will permanently delete the service.")
        #expect(service.activeAlert?.primaryButton.title == "Delete")
        #expect(service.activeAlert?.primaryButton.role == .destructive)
        #expect(service.activeAlert?.secondaryButton?.title == "Cancel")
        #expect(service.activeAlert?.secondaryButton?.role == .cancel)
    }

    // MARK: - [TC-D03] Dismiss Clears Payload
    @Test("TC-D03: dismiss resets activeAlert to nil")
    func testDismissAlertClearsActiveAlert() {
        let service = AlertService.shared
        service.showError(
            title: "Warning",
            message: "Action required"
        )
        #expect(service.activeAlert != nil)

        service.dismiss()
        #expect(service.activeAlert == nil)
    }

    // MARK: - [TC-D04] Button Action Callbacks
    @Test("TC-D04: Button action closures execute reliably on MainActor")
    func testAlertButtonRolesAndActionCallbacks() {
        var actionExecuted = false

        let button = KumaAlertButton(title: "Confirm", role: nil) {
            actionExecuted = true
        }

        #expect(actionExecuted == false)
        button.action?()
        #expect(actionExecuted == true)
    }

    // MARK: - [TC-D05] Rapid Consecutive Alerts (Single-Slot Modal)
    @Test("TC-D05: Consecutive show calls replace the existing payload cleanly")
    func testRapidConsecutiveAlertsReplacement() {
        let service = AlertService.shared
        defer { service.dismiss() }

        service.show(
            title: "First Alert",
            message: "Message 1",
            primaryButton: .primary(title: "OK 1")
        )
        #expect(service.activeAlert?.title == "First Alert")

        service.show(
            title: "Second Alert",
            message: "Message 2",
            primaryButton: .primary(title: "OK 2")
        )
        #expect(service.activeAlert?.title == "Second Alert")
        #expect(service.activeAlert?.message == "Message 2")
    }
}
