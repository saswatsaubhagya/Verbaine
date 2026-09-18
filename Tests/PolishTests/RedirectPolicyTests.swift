import Foundation
import Testing
@testable import Polish

/// F3: `URLSession` forwards the `Authorization` header across redirects, including cross-host
/// ones, unless something strips it first. `RedirectPolicy.sanitizedRequest` is that something —
/// factored out as a pure function so the host check is testable without a socket or a delegate
/// callback.
private func authorizedRequest(to urlString: String) -> URLRequest {
    var request = URLRequest(url: URL(string: urlString)!)
    request.setValue("Bearer sk-test-secret", forHTTPHeaderField: "Authorization")
    return request
}

@Test("a same-host redirect keeps the Authorization header")
func sameHostRedirectKeepsAuthorization() {
    let redirected = authorizedRequest(to: "https://api.example.com/v1/other-path")
    let sanitized = RedirectPolicy.sanitizedRequest(originalHost: "api.example.com", redirectedTo: redirected)
    #expect(sanitized.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret")
}

@Test("a cross-host redirect drops the Authorization header")
func crossHostRedirectDropsAuthorization() {
    let redirected = authorizedRequest(to: "https://evil.example.com/v1/other-path")
    let sanitized = RedirectPolicy.sanitizedRequest(originalHost: "api.example.com", redirectedTo: redirected)
    #expect(sanitized.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test("a subdomain is still a different host, so the key does not follow it")
func subdomainRedirectDropsAuthorization() {
    let redirected = authorizedRequest(to: "https://sneaky.api.example.com/v1/other-path")
    let sanitized = RedirectPolicy.sanitizedRequest(originalHost: "api.example.com", redirectedTo: redirected)
    #expect(sanitized.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test("a nil original host — a malformed base URL — never lets the key ride along")
func nilOriginalHostDropsAuthorization() {
    let redirected = authorizedRequest(to: "https://api.example.com/v1/other-path")
    let sanitized = RedirectPolicy.sanitizedRequest(originalHost: nil, redirectedTo: redirected)
    #expect(sanitized.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test("everything else about the redirected request is left untouched")
func sameHostRedirectKeepsOtherHeaders() {
    var redirected = authorizedRequest(to: "https://api.example.com/v1/other-path")
    redirected.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let sanitized = RedirectPolicy.sanitizedRequest(originalHost: "api.example.com", redirectedTo: redirected)
    #expect(sanitized.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(sanitized.url == redirected.url)
}
