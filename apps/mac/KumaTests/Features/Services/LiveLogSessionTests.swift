import Foundation
import Testing
@testable import Kuma

@Suite("Feature 05: Live log session", .serialized)
struct LiveLogSessionTests {

    @Test("TC-L03: ANSISanitizer strips terminal escape codes")
    func testANSISanitizerStripsColors() {
        let colored = "\u{001B}[32mSUCCESS\u{001B}[0m: done."
        #expect(ANSISanitizer.sanitize(colored) == "SUCCESS: done.")
    }

    @Test("TC-L14: beginRun resets buffer; lines persist without panel attach")
    @MainActor
    func testBeginRunResetsAndPersistsWithoutPanel() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: serviceID, message: "first")
        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: serviceID, message: "second")
        #expect(session.lines(for: serviceID).count == 1)
        #expect(session.lines(for: serviceID)[0].text == "[KUMA] second")
        session.clearAll()
    }

    @Test("TC-L13: lines remain after capture ends until clear or beginRun")
    @MainActor
    func testLinesPersistAfterCaptureUntilCleared() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: serviceID, message: "kept")
        session.endCapture(serviceID: serviceID)
        session.emitSystem(serviceID: serviceID, message: "ignored")
        #expect(session.lines(for: serviceID).count == 1)
        session.clear(serviceID: serviceID)
        session.emitSystem(serviceID: serviceID, message: "ignored")
        #expect(session.lines(for: serviceID).isEmpty)
        session.clearAll()
    }

    @Test("TC-L15: emitSystem requires beginRun and matching serviceID")
    @MainActor
    func testEmitSystemRequiresBeginRun() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.emitSystem(serviceID: serviceID, message: "ignored")
        #expect(session.lines(for: serviceID).isEmpty)

        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: UUID(), message: "wrong service")
        #expect(session.lines(for: serviceID).isEmpty)

        session.emitSystem(serviceID: serviceID, message: "hello")
        #expect(session.lines(for: serviceID).count == 1)
        #expect(session.lines(for: serviceID)[0].text == "[KUMA] hello")
        #expect(session.lines(for: serviceID)[0].kind == .system)
        session.clearAll()
    }

    @Test("TC-L17: per-service buffers are isolated")
    @MainActor
    func testPerServiceBufferIsolation() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceA = UUID()
        let serviceB = UUID()
        session.testing_beginRun(serviceA)
        session.emitSystem(serviceID: serviceA, message: "A")
        session.testing_beginRun(serviceB)
        session.emitSystem(serviceID: serviceB, message: "B")
        #expect(session.lines(for: serviceA).count == 1)
        #expect(session.lines(for: serviceB).count == 1)
        session.testing_beginRun(serviceA)
        #expect(session.lines(for: serviceA).isEmpty)
        #expect(session.lines(for: serviceB).count == 1)
        session.clearAll()
    }

    @Test("TC-L18: recordBannerFailure keeps multiline detail")
    @MainActor
    func testRecordBannerFailureMultiline() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.recordBannerFailure(serviceID: serviceID, message: "line one\nline two")
        #expect(session.lines(for: serviceID).count == 2)
        #expect(session.lines(for: serviceID)[0].text == "[FAILURE] line one")
        #expect(session.lines(for: serviceID)[1].text == "  line two")
        session.recordBannerFailure(serviceID: serviceID, message: "line one\nline two")
        #expect(session.lines(for: serviceID).count == 2)
        session.clearAll()
    }

    @Test("TC-L20: endCapture stops emitSystem but preserves lines")
    @MainActor
    func testEndCaptureStopsEmitPreservesLines() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: serviceID, message: "visible")
        session.endCapture(serviceID: serviceID)
        session.emitSystem(serviceID: serviceID, message: "hidden")
        #expect(session.lines(for: serviceID).count == 1)
        session.clearAll()
    }

    @Test("TC-L21: LRU evicts least recently touched service buffer")
    @MainActor
    func testLRUEvictsOldestServiceBuffer() {
        let session = LiveLogSession.shared
        session.clearAll()
        session.testing_setMaxRetainedServices(2)
        let first = UUID()
        let second = UUID()
        let third = UUID()
        session.testing_beginRun(first)
        session.emitSystem(serviceID: first, message: "first")
        session.testing_beginRun(second)
        session.emitSystem(serviceID: second, message: "second")
        session.markRecentlyUsed(serviceID: second)
        session.testing_beginRun(third)
        session.emitSystem(serviceID: third, message: "third")
        #expect(session.lines(for: first).isEmpty)
        #expect(session.lines(for: second).count == 1)
        #expect(session.lines(for: third).count == 1)
        session.testing_setMaxRetainedServices(50)
        session.clearAll()
    }

    @Test("TC-L22: emitSystemBatch appends multiple lines in one call")
    @MainActor
    func testEmitSystemBatch() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        session.emitSystemBatch(serviceID: serviceID, messages: ["one", "two"])
        #expect(session.lines(for: serviceID).count == 2)
        #expect(session.lines(for: serviceID)[0].text == "[KUMA] one")
        #expect(session.revision(for: serviceID) >= 2)
        session.clearAll()
    }

    @Test("TC-L23: recordBannerFailure skips duplicate of Start failed line")
    @MainActor
    func testRecordBannerFailureSkipsStartFailedDuplicate() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: serviceID, message: "Start failed: port in use")
        session.recordBannerFailure(serviceID: serviceID, message: "port in use")
        #expect(session.lines(for: serviceID).count == 1)
        session.clearAll()
    }

    @Test("TC-L10: LiveLogSession ring buffer caps at 1000 lines per service")
    @MainActor
    func testLiveLogSessionRingBufferCap() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        for index in 0..<1_100 {
            session.emitSystem(serviceID: serviceID, message: "line \(index)")
        }
        #expect(session.lines(for: serviceID).count == 1_000)
        #expect(session.lines(for: serviceID).last?.text == "[KUMA] line 1099")
        #expect(session.didTrimToMaxLines(for: serviceID))
        session.clearAll()
    }

    @Test("TC-L24: emitSystem assigns kuma category")
    @MainActor
    func testEmitSystemCategoryKuma() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.testing_beginRun(serviceID)
        session.emitSystem(serviceID: serviceID, message: "Starting")
        #expect(session.lines(for: serviceID).first?.category == .kuma)
        session.clearAll()
    }

    @Test("TC-L25: recordBannerFailure assigns failure and continuation categories")
    @MainActor
    func testRecordBannerFailureCategories() {
        let session = LiveLogSession.shared
        session.clearAll()
        let serviceID = UUID()
        session.recordBannerFailure(serviceID: serviceID, message: "one\ntwo")
        let lines = session.lines(for: serviceID)
        #expect(lines.count == 2)
        #expect(lines[0].category == .failure)
        #expect(lines[1].category == .failureContinuation)
        session.clearAll()
    }

    @Test("TC-L26: ActivityLogFormatting strips prefixes for UI")
    @MainActor
    func testActivityLogFormattingStripsPrefixes() {
        #expect(
            ActivityLogFormatting.displayMessage(from: "[KUMA] Starting", category: .kuma) == "Starting"
        )
        #expect(
            ActivityLogFormatting.displayMessage(from: "[FAILURE] oops", category: .failure) == "oops"
        )
        #expect(
            ActivityLogFormatting.displayMessage(from: "  detail", category: .failureContinuation) == "detail"
        )
    }
}
