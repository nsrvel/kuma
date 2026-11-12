import Foundation

/// Utility for normalizing user-entered endpoint URLs for Health Checks, Tunnels, and Services.
/// Automatically handles missing schemes, localhost ports, subdomains, and scheme sanitization.
public nonisolated enum URLNormalizer {

    /// Normalizes a raw string into a fully qualified HTTP/HTTPS URL string.
    ///
    /// Examples:
    /// - `"google.com"` -> `"https://google.com"`
    /// - `"http.google.com"` -> `"https://http.google.com"`
    /// - `"http://google.com"` -> `"http://google.com"`
    /// - `"https://google.com/health"` -> `"https://google.com/health"`
    /// - `"localhost:3000"` -> `"http://localhost:3000"`
    /// - `"127.0.0.1:8080/health"` -> `"http://127.0.0.1:8080/health"`
    /// - `"3000"` -> `"http://localhost:3000"`
    ///
    /// - Parameters:
    ///   - raw: The raw input string from user or configuration.
    ///   - defaultToHttps: Whether external domains without scheme should default to `https://`. Defaults to `true`.
    /// - Returns: A valid URL string, or `nil` if the input cannot form a valid URL.
    public static func normalize(_ raw: String, defaultToHttps: Bool = true) -> String? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip surrounding quotes if present
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
        }

        // Case 1: Pure port number (e.g. "3000" or ":3000")
        let portString = trimmed.hasPrefix(":") ? String(trimmed.dropFirst()) : trimmed
        if let port = Int(portString), port > 0, port <= 65535 {
            return "http://localhost:\(port)"
        }

        // Case 2: Already has a scheme
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return isValidURL(trimmed) ? trimmed : nil
        }

        // Case 3: Common scheme typos like "http:/" or "https:/" or "http//"
        if let fixedScheme = fixMalformedScheme(trimmed) {
            return isValidURL(fixedScheme) ? fixedScheme : nil
        }

        // Case 4: Missing scheme - Determine default scheme (http for local/IP, https for external)
        let isLocal = isLocalhostOrLoopback(trimmed)
        let scheme = (isLocal || !defaultToHttps) ? "http://" : "https://"
        let candidate = "\(scheme)\(trimmed)"

        return isValidURL(candidate) ? candidate : nil
    }

    // MARK: - Private Helpers

    private static func fixMalformedScheme(_ input: String) -> String? {
        let lower = input.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return input
        }
        if lower.hasPrefix("http:/") && !lower.hasPrefix("http://") {
            return "http://" + input.dropFirst("http:/".count)
        }
        if lower.hasPrefix("https:/") && !lower.hasPrefix("https://") {
            return "https://" + input.dropFirst("https:/".count)
        }
        if lower.hasPrefix("http//") {
            return "http://" + input.dropFirst("http//".count)
        }
        if lower.hasPrefix("https//") {
            return "https://" + input.dropFirst("https//".count)
        }
        return nil
    }

    private static func isLocalhostOrLoopback(_ hostAndPath: String) -> Bool {
        let lower = hostAndPath.lowercased()
        let hostPart = lower.split(separator: "/").first ?? ""
        let hostWithoutPort = hostPart.split(separator: ":").first ?? ""

        return hostWithoutPort == "localhost" ||
               hostWithoutPort == "127.0.0.1" ||
               hostWithoutPort == "0.0.0.0" ||
               hostWithoutPort == "::1" ||
               hostWithoutPort.hasSuffix(".local")
    }

    private static func isValidURL(_ candidate: String) -> Bool {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
}
