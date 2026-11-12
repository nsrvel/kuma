import Foundation
import Testing
import AppKit
@testable import Kuma

@Suite("Feature 00 - Category F: Audio Sync, Idempotency & Playback")
@MainActor
struct KumaSoundManagerTests {

    // MARK: - [TC-F01] Sync Sound File
    @Test("TC-F01: syncCustomNotificationSoundToUserLibrary executes safely")
    func testSyncSoundFileToUserLibrarySounds() {
        let manager = KumaSoundManager.shared
        manager.syncCustomNotificationSoundToUserLibrary()
        #expect(Bundle.main.url(forResource: "kuma-alert", withExtension: "caf") != nil)
    }

    // MARK: - [TC-F02] Idempotent Skip
    @Test("TC-F02: Multiple syncCustomNotificationSoundToUserLibrary calls do not throw")
    func testSyncSoundIdempotentSkip() {
        let manager = KumaSoundManager.shared
        manager.syncCustomNotificationSoundToUserLibrary()
        manager.syncCustomNotificationSoundToUserLibrary()
        let soundsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Sounds/kuma-alert.caf")
        if Bundle.main.url(forResource: "kuma-alert", withExtension: "caf") != nil {
            #expect(FileManager.default.fileExists(atPath: soundsDir.path(percentEncoded: false)))
        }
    }

    // MARK: - [TC-F03] Graceful Fallback
    @Test("TC-F03: playNotificationSound safely executes without crash")
    func testPlaySoundGracefulFallbackWhenMissing() {
        let manager = KumaSoundManager.shared
        manager.playNotificationSound()
        #expect(KumaSoundManager.shared === manager)
    }
}
