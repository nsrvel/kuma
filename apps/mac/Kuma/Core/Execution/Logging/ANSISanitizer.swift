import Foundation

/// Fast utility to strip terminal ANSI escape sequences (colors, cursor codes, OSC sequences)
/// and normalize carriage return control characters so logs render cleanly in SwiftUI.
public nonisolated enum ANSISanitizer {

    // Regex matching standard ANSI escape sequences:
    // 1. CSI sequences: ESC [ ... [a-zA-Z]
    // 2. OSC sequences: ESC ] ... (BEL | ESC \)
    // 3. Simple ESC sequences: ESC followed by single char (e.g. ESC ( B)
    private static let ansiRegex: NSRegularExpression? = {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\].*?(?:\x07|\x1B\\))"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    /// Strips ANSI escape sequences and carriage return artifacts from raw process output.
    ///
    /// - Parameter text: Raw stdout/stderr string.
    /// - Returns: Clean human-readable string suitable for display.
    public static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        // 1. Replace carriage return carriage returns (e.g. progress spinners \r)
        var cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")

        // 2. Fast-path check: If no ESC byte (0x1B), skip regex processing
        guard cleaned.unicodeScalars.contains(where: { $0.value == 0x1B }) else {
            return cleaned
        }

        guard let regex = ansiRegex else { return cleaned }
        let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        return regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
    }
}
