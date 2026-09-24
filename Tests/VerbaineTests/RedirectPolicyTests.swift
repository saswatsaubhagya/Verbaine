import Foundation
import Testing
@testable import Verbaine

/// F3/F6: `URLSession` follows both the `Authorization` header and the request body — the
/// user's selected text — across a redirect, including a cross-host one. `RedirectPolicy`
/// answers a single question, "should this redirect be followed at all," and refusing it
/// outright is what protects the body as well as the key. Factored out as a pure function so the
/// host check is testable without a socket or a delegate callback.
private func request(to urlString: String) -> URLRequest {
    URLRequest(url: URL(string: urlString)!)
}

private func url(_ string: String) -> URL { URL(string: string)! }

/// The origin every test below redirects away from.
private let origin = url("https://api.example.com/v1/chat/completions")

private func allows(_ target: String, from original: URL? = origin) -> Bool {
    RedirectPolicy.allowsRedirect(original: original, to: request(to: target))
}

@Test("a same-host redirect is allowed")
func sameHostRedirectIsAllowed() {
    #expect(allows("https://api.example.com/v1/other-path"))
}

@Test("a cross-host redirect is refused outright, not just stripped of its key")
func crossHostRedirectIsRefused() {
    #expect(!allows("https://evil.example.com/v1/other-path"))
}

@Test("a subdomain is still a different host, so the redirect is refused")
func subdomainRedirectIsRefused() {
    #expect(!allows("https://sneaky.api.example.com/v1/other-path"))
}

@Test("a nil original URL — a malformed base URL — never allows a redirect")
func nilOriginalHostRefusesRedirect() {
    #expect(!allows("https://api.example.com/v1/other-path", from: nil))
}

@Test("a nil original URL and a hostless target never compare equal — always refused")
func nilRedirectedHostNeverMatchesNilOriginalHost() {
    // A `file:` URL reports no host at all, giving a `nil` on both sides of the comparison —
    // exactly the case a bare `==` would wrongly treat as a match.
    #expect(!allows("file:///tmp/exfiltrate", from: nil))
}

@Test("a redirect target with no host at all is refused even against a real original host")
func redirectWithNoHostIsRefused() {
    #expect(!allows("file:///tmp/exfiltrate"))
}


// MARK: - M5: the origin is scheme + host + port, not the host alone

@Test("a same-host redirect that downgrades https to http is refused")
func schemeDowngradeIsRefused() {
    // ATS blocks this hop today; the guard must not be relying on that.
    #expect(!allows("http://api.example.com/v1/other-path"))
}

@Test("a same-host redirect that upgrades http to https is still a different origin, so refused")
func schemeUpgradeIsRefused() {
    #expect(!allows("https://localhost:11434/v1/other-path", from: url("http://localhost:11434/v1/chat/completions")))
}

@Test("a same-host redirect to a different port is refused")
func portChangeIsRefused() {
    #expect(!allows("https://api.example.com:8443/v1/other-path"))
}

@Test("a local endpoint redirected to another local port is refused")
func localPortHopIsRefused() {
    #expect(!allows("http://localhost:1234/v1/other-path", from: url("http://localhost:11434/v1/chat/completions")))
}

@Test("an explicit default port is the same origin as an implicit one, in both directions")
func explicitDefaultPortMatchesImplicitOne() {
    #expect(allows("https://api.example.com:443/v1/other-path"))
    #expect(allows("https://api.example.com/v1/other-path", from: url("https://api.example.com:443/v1/chat/completions")))
    #expect(allows("http://localhost:80/v1/x", from: url("http://localhost/v1/chat/completions")))
}

@Test("a same-origin redirect whose host differs only in case is allowed, not needlessly refused")
func caseDifferingHostIsAllowed() {
    #expect(allows("https://API.Example.COM/v1/other-path"))
    #expect(allows("https://api.example.com/v1/other-path", from: url("https://API.EXAMPLE.com/v1/chat/completions")))
}

@Test("case-insensitivity does not weaken the host check — a different host in any case is refused")
func caseInsensitivityDoesNotAdmitAnotherHost() {
    #expect(!allows("https://EVIL.example.com/v1/other-path"))
}

@Test("a scheme written in upper case is still the same scheme")
func upperCaseSchemeMatches() {
    #expect(allows("HTTPS://api.example.com/v1/other-path"))
}
