import Testing
@testable import Kuma

@Suite("KumaDualSourceMode")
struct KumaDualSourceModeTests {
    @Test("prefers file path when both path and text are set")
    func inferredPrefersPath() {
        let mode = KumaDualSourceMode.inferred(
            path: "/tmp/compose.yml",
            text: "services:",
            fallback: .pasteYAML
        )
        #expect(mode == .chooseFile)
    }

    @Test("uses paste when path is empty")
    func inferredUsesTextWhenPathEmpty() {
        let mode = KumaDualSourceMode.inferred(
            path: "  ",
            text: "services:\n  web:",
            fallback: .chooseFile
        )
        #expect(mode == .pasteYAML)
    }

    @Test("falls back when both are empty")
    func inferredFallbackWhenBothEmpty() {
        #expect(KumaDualSourceMode.inferred(path: "", text: "", fallback: .chooseFile) == .chooseFile)
        #expect(KumaDualSourceMode.inferred(path: "", text: "", fallback: .pasteYAML) == .pasteYAML)
    }
}
