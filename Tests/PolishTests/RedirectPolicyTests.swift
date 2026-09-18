import Foundation
import Testing
@testable import Polish

/// F3/F6: `URLSession` follows both the `Authorization` header and the request body — the
/// user's selected text — across a redirect, including a cross-host one. `RedirectPolicy`
/// answers a single question, "should this redirect be followed at all," and refusing it
/// outright is what protects the body as well as the key. Factored out as a pure function so the
/// host check is testable without a socket or a delegate callback.
private func request(to urlString: String) -> URLRequest {
    URLRequest(url: URL(string: urlString)!)
}

@Test("a same-host redirect is allowed")
func sameHostRedirectIsAllowed() {
    #expect(RedirectPolicy.allowsRedirect(originalHost: "api.example.com", to: request(to: "https://api.example.com/v1/other-path")))
}

@Test("a cross-host redirect is refused outright, not just stripped of its key")
func crossHostRedirectIsRefused() {
    #expect(!RedirectPolicy.allowsRedirect(originalHost: "api.example.com", to: request(to: "https://evil.example.com/v1/other-path")))
}

@Test("a subdomain is still a different host, so the redirect is refused")
func subdomainRedirectIsRefused() {
    #expect(!RedirectPolicy.allowsRedirect(originalHost: "api.example.com", to: request(to: "https://sneaky.api.example.com/v1/other-path")))
}

@Test("a nil original host — a malformed base URL — never allows a redirect")
func nilOriginalHostRefusesRedirect() {
    #expect(!RedirectPolicy.allowsRedirect(originalHost: nil, to: request(to: "https://api.example.com/v1/other-path")))
}

@Test("two nil hosts never compare equal — a redirect to a request with no host is always refused")
func nilRedirectedHostNeverMatchesNilOriginalHost() {
    // A `file:` URL reports no host at all, giving a `nil` on both sides of the comparison —
    // exactly the case a bare `==` would wrongly treat as a match.
    #expect(!RedirectPolicy.allowsRedirect(originalHost: nil, to: request(to: "file:///tmp/exfiltrate")))
}

@Test("a redirect target with no host at all is refused even against a real original host")
func redirectWithNoHostIsRefused() {
    #expect(!RedirectPolicy.allowsRedirect(originalHost: "api.example.com", to: request(to: "file:///tmp/exfiltrate")))
}
