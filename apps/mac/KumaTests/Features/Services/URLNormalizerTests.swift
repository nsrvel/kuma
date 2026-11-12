import Foundation
import Testing
@testable import Kuma

@Suite("Feature 05: URL Normalizer Tests", .serialized)
struct URLNormalizerTests {

    @Test("TC-U01: External domain defaults to HTTPS")
    func testExternalDomainDefaultsToHttps() {
        let result = URLNormalizer.normalize("google.com")
        #expect(result == "https://google.com")
    }

    @Test("TC-U02: Subdomain preserves subdomain and applies HTTPS")
    func testSubdomainPreserved() {
        let result = URLNormalizer.normalize("http.google.com")
        #expect(result == "https://http.google.com")
    }

    @Test("TC-U03: Explicit HTTP and HTTPS schemes are preserved")
    func testExplicitSchemesPreserved() {
        let httpResult = URLNormalizer.normalize("http://google.com/search?q=kuma")
        #expect(httpResult == "http://google.com/search?q=kuma")

        let httpsResult = URLNormalizer.normalize("https://google.com/healthz")
        #expect(httpsResult == "https://google.com/healthz")
    }

    @Test("TC-U04: Localhost and Loopback IP default to HTTP")
    func testLocalhostDefaultsToHttp() {
        let localhost = URLNormalizer.normalize("localhost:3000/api")
        #expect(localhost == "http://localhost:3000/api")

        let ip = URLNormalizer.normalize("127.0.0.1:8080/health")
        #expect(ip == "http://127.0.0.1:8080/health")

        let zeroIP = URLNormalizer.normalize("0.0.0.0:5000")
        #expect(zeroIP == "http://0.0.0.0:5000")
    }

    @Test("TC-U05: Pure port number normalizes to localhost HTTP")
    func testPortNumberNormalizesToLocalhost() {
        let portOnly = URLNormalizer.normalize("3000")
        #expect(portOnly == "http://localhost:3000")

        let colonPort = URLNormalizer.normalize(":8080")
        #expect(colonPort == "http://localhost:8080")
    }

    @Test("TC-U06: Common typo schemes are corrected")
    func testTypoSchemesCorrected() {
        let singleSlash = URLNormalizer.normalize("http:/google.com")
        #expect(singleSlash == "http://google.com")

        let missingColon = URLNormalizer.normalize("https//api.example.com")
        #expect(missingColon == "https://api.example.com")
    }

    @Test("TC-U07: Whitespace and quoted strings are sanitized")
    func testWhitespaceAndQuotesSanitized() {
        let quoted = URLNormalizer.normalize("\"  google.com  \"")
        #expect(quoted == "https://google.com")

        let singleQuoted = URLNormalizer.normalize("'localhost:4000'")
        #expect(singleQuoted == "http://localhost:4000")
    }

    @Test("TC-U08: Blank and invalid inputs return nil")
    func testInvalidInputsReturnNil() {
        #expect(URLNormalizer.normalize("") == nil)
        #expect(URLNormalizer.normalize("   ") == nil)
        #expect(URLNormalizer.normalize("://") == nil)
    }
}
