import Foundation
import Testing
@testable import Polish

/// A host nobody will ever configure, so the test cannot collide with a real stored key.
private func scratchHost() -> String { "test-\(UUID().uuidString).invalid" }

@Test("a key saves, loads back, overwrites and deletes")
func keyRoundTrips() throws {
    let host = scratchHost()
    defer { try? APIKeyStore.delete(forHost: host) }

    #expect(APIKeyStore.load(forHost: host) == nil)

    try APIKeyStore.save("sk-first", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == "sk-first")

    // Saving again must replace, not fail with errSecDuplicateItem.
    try APIKeyStore.save("sk-second", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == "sk-second")

    try APIKeyStore.delete(forHost: host)
    #expect(APIKeyStore.load(forHost: host) == nil)
}

@Test("keys for two hosts do not see each other")
func keysAreScopedToHost() throws {
    let first = scratchHost()
    let second = scratchHost()
    defer {
        try? APIKeyStore.delete(forHost: first)
        try? APIKeyStore.delete(forHost: second)
    }

    try APIKeyStore.save("sk-openai", forHost: first)
    try APIKeyStore.save("sk-groq", forHost: second)

    #expect(APIKeyStore.load(forHost: first) == "sk-openai")
    #expect(APIKeyStore.load(forHost: second) == "sk-groq")
}

@Test("deleting a key that was never there is not an error")
func deletingAbsentKeyIsFine() throws {
    try APIKeyStore.delete(forHost: scratchHost())
}

@Test("saving an empty key clears any key already stored for that host")
func savingEmptyKeyDeletes() throws {
    let host = scratchHost()
    defer { try? APIKeyStore.delete(forHost: host) }

    try APIKeyStore.save("sk-value", forHost: host)
    try APIKeyStore.save("", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == nil)
}

/// Guards the F2 fix: `save` no longer deletes before adding, so overwriting many times in a
/// row must never leave the host without a key in between.
@Test("overwriting a key repeatedly never leaves the host without one")
func overwritingNeverLeavesHostEmpty() throws {
    let host = scratchHost()
    defer { try? APIKeyStore.delete(forHost: host) }

    try APIKeyStore.save("sk-a", forHost: host)
    try APIKeyStore.save("sk-b", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == "sk-b")
    try APIKeyStore.save("sk-c", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == "sk-c")
}
