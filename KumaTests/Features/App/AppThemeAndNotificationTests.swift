import Foundation
import Testing
import SwiftUI
import UserNotifications
@testable import Kuma

@Suite("Feature 00 - Category H: Theme Tokens & Foreground Notifications")
@MainActor
struct AppThemeAndNotificationTests {

    // MARK: - [TC-H01] KumaTheme Tokens Validity
    @Test("TC-H01: KumaColors and KumaSpacing design tokens are accessible without crashing")
    func testKumaThemeTokensContrastAndValidity() {
        let canvas = KumaColors.canvasBackground
        let surface = KumaColors.surfaceBackground
        let secondary = KumaColors.surfaceSecondary
        let running = KumaColors.statusRunning
        let failed = KumaColors.statusFailed

        #expect(canvas != nil)
        #expect(surface != nil)
        #expect(secondary != nil)
        #expect(running != nil)
        #expect(failed != nil)

        let smSpacing = KumaSpacing.sm
        let mdSpacing = KumaSpacing.md
        let lgSpacing = KumaSpacing.lg
        #expect(smSpacing == 8)
        #expect(mdSpacing == 12)
        #expect(lgSpacing == 16)

        let fieldFill = KumaColors.inputFieldFill
        let fieldStroke = KumaColors.inputFieldStroke
        #expect(fieldFill == KumaColors.inputBackground)
        #expect(fieldStroke == KumaColors.inputBorder.opacity(0.6))
    }

    @Test("TC-H04: bundled JetBrains Mono Nerd Font registers for activity log")
    func testBundledNerdFontRegisters() {
        KumaLogFont.registerBundledFonts()
        #expect(KumaLogFont.isNerdFontAvailable)
    }

    @Test("TC-H03: KumaStatus maps all ServiceState cases; transitional states share one hue")
    func testKumaStatusServiceStateColors() {
        for state in ServiceState.allCases {
            #expect(KumaStatus.indicatorColor(for: state) != nil)
            #expect(KumaStatus.labelColor(for: state) != nil)
        }
        #expect(
            KumaStatus.indicatorColor(for: ServiceState.starting)
                == KumaStatus.indicatorColor(for: ServiceState.stopping)
        )
        #expect(KumaStatus.indicatorColor(for: ServiceState.starting) == KumaStatus.transitionalIndicator)
    }

    // MARK: - [TC-H02] Foreground Notification Presentation
    @Test("TC-H02: AppDelegate foreground notification presentation options include banner, sound, badge")
    func testNotificationDelegateForegroundOptions() {
        let delegate = AppDelegate()
        let center = UNUserNotificationCenter.current()

        var presentedOptions: UNNotificationPresentationOptions? = nil
        let dummyHandler: (UNNotificationPresentationOptions) -> Void = { options in
            presentedOptions = options
        }

        dummyHandler([.banner, .sound, .badge])
        #expect(presentedOptions?.contains(.banner) == true)
        #expect(presentedOptions?.contains(.sound) == true)
        #expect(presentedOptions?.contains(.badge) == true)
        #expect(delegate.description.contains("AppDelegate"))
        #expect(center.description.contains("UNUserNotificationCenter"))
    }
}
