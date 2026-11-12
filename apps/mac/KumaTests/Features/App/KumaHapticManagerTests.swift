import AppKit
import Testing
@testable import Kuma

// MARK: - Mock Performer

private final class MockHapticPerformer: NSObject, NSHapticFeedbackPerformer {
    nonisolated(unsafe) var performedPatterns: [NSHapticFeedbackManager.FeedbackPattern] = []

    nonisolated func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) {
        performedPatterns.append(pattern)
    }
}

// MARK: - KumaHapticManagerTests

@Suite("Feature 00 - Category G: Native Trackpad Haptic Feedback Manager")
@MainActor
struct KumaHapticManagerTests {

    @Test("TC-G01: KumaHapticManager fires generic pattern on tap()")
    func testHapticTap() {
        let mock = MockHapticPerformer()
        let manager = KumaHapticManager(performer: mock)
        manager.tap()
        #expect(mock.performedPatterns == [.generic])
    }

    @Test("TC-G02: KumaHapticManager fires alignment pattern on alignment()")
    func testHapticAlignment() {
        let mock = MockHapticPerformer()
        let manager = KumaHapticManager(performer: mock)
        manager.alignment()
        #expect(mock.performedPatterns == [.alignment])
    }

    @Test("TC-G03: KumaHapticManager fires levelChange pattern on levelChange()")
    func testHapticLevelChange() {
        let mock = MockHapticPerformer()
        let manager = KumaHapticManager(performer: mock)
        manager.levelChange()
        #expect(mock.performedPatterns == [.levelChange])
    }

}
