import Foundation

/// Set before any app code runs so production hooks can detect the Swift Testing host.
private enum TestHostMarker {
    static let activate: Void = {
        setenv("KUMA_UNIT_TESTS", "1", 1)
    }()
}

private let _kumaTestHostMarker: Void = TestHostMarker.activate
