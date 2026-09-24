import Foundation
import Testing
@testable import Polish

/// A host nobody will ever configure, so the test cannot collide with a real stored key.
private func scratchHost() -> String { "test-\(UUID().uuidString).invalid" }

/// Covers the F1 fix: `ModelSettings` reloads the API-key field from the new host as soon as the
/// endpoint's host changes, rather than leaving the previous host's key sitting in the field
/// where the next keystroke would save it under the wrong host.
@Test("changing the host reloads the field with that host's own key, not the previous host's")
func apiKeyOnHostChangeUsesTheNewHostsOwnKey() throws {
    let first = scratchHost()
    let second = scratchHost()
    defer {
        try? APIKeyStore.delete(forHost: first)
        try? APIKeyStore.delete(forHost: second)
    }

    try APIKeyStore.save("sk-first", forHost: first)
    try APIKeyStore.save("sk-second", forHost: second)

    #expect(ModelSettings.apiKeyOnHostChange(to: first) == "sk-first")
    #expect(ModelSettings.apiKeyOnHostChange(to: second) == "sk-second")
}

@Test("a host with no stored key reloads to an empty field rather than the old value")
func apiKeyOnHostChangeIsEmptyForAnUnconfiguredHost() {
    #expect(ModelSettings.apiKeyOnHostChange(to: scratchHost()) == "")
}

@Test("a nil host (an incomplete base URL) reloads to an empty field")
func apiKeyOnHostChangeIsEmptyForNoHost() {
    #expect(ModelSettings.apiKeyOnHostChange(to: nil) == "")
}

/// The bug F1 fixes: without the reload, saving whatever the field currently holds right after
/// switching hosts would file the first host's key under the second host. This drives the exact
/// sequence the view performs — reload, then save — and checks neither host ends up with the
/// wrong key.
@Test("reload-then-save after a host change never files one host's key under another")
func reloadThenSaveDoesNotLeakAcrossHosts() throws {
    let first = scratchHost()
    let second = scratchHost()
    defer {
        try? APIKeyStore.delete(forHost: first)
        try? APIKeyStore.delete(forHost: second)
    }

    try APIKeyStore.save("sk-first", forHost: first)

    // Simulate switching the base URL to the second host: reload what the field should show,
    // then save it back (what `saveKey()` does on the next `onChange(of: apiKey)`).
    let reloaded = ModelSettings.apiKeyOnHostChange(to: second)
    try APIKeyStore.save(reloaded, forHost: second)

    #expect(APIKeyStore.load(forHost: first) == "sk-first")
    #expect(APIKeyStore.load(forHost: second) == nil)
}

/// Covers the F2 fix: a Keychain failure must surface as a status code the user can see, never
/// silently swallowed and never carrying the key.
@Test("a Keychain failure surfaces its status code, and only the status code")
func keySaveErrorMessageShowsStatusOnly() {
    let message = ModelSettings.keySaveErrorMessage(for: APIKeyStore.StoreError.keychain(-34018))
    #expect(message == "Could not save the key (Keychain status -34018).")
}

@Test("a non-Keychain error produces no message")
func keySaveErrorMessageIgnoresOtherErrors() {
    struct OtherError: Error {}
    #expect(ModelSettings.keySaveErrorMessage(for: OtherError()) == nil)
}
