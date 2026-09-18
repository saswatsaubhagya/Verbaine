import Foundation
import Testing
@testable import Polish

/// A defaults domain of its own per test, so nothing touches the real preferences.
private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "polish.tests.\(UUID().uuidString)")!
}

@Test("the provider falls back to the on-device model and round-trips")
func providerKindPersists() {
    let defaults = scratchDefaults()
    #expect(Preferences.providerKind(defaults) == .apple)

    Preferences.setProviderKind(.remote, defaults)
    #expect(Preferences.providerKind(defaults) == .remote)

    // A value written by an older or newer build must not strand the user on a provider the app
    // cannot resolve.
    defaults.set("anthropic-native", forKey: Preferences.providerKindKey)
    #expect(Preferences.providerKind(defaults) == .apple)
}

@Test("a remote config round-trips and defaults to a 128k window")
func remoteConfigPersists() {
    let defaults = scratchDefaults()
    #expect(Preferences.remoteConfig(defaults).contextSize == 128_000)
    #expect(Preferences.remoteConfig(defaults).isComplete == false)

    let config = RemoteConfig(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", contextSize: 128_000)
    Preferences.setRemoteConfig(config, defaults)
    #expect(Preferences.remoteConfig(defaults) == config)
    #expect(Preferences.remoteConfig(defaults).isComplete)
}

@Test("a config is incomplete until both the URL and the model name are filled in", arguments: [
    ("", "gpt-4o-mini"),
    ("https://api.openai.com/v1", ""),
    ("   ", "   "),
])
func incompleteConfig(baseURL: String, model: String) {
    let config = RemoteConfig(baseURL: baseURL, model: model, contextSize: 128_000)
    #expect(config.isComplete == false)
}

@Test("the chat endpoint is built from the base URL, with or without a trailing slash", arguments: [
    "https://api.openai.com/v1",
    "https://api.openai.com/v1/",
])
func endpointURL(baseURL: String) {
    let config = RemoteConfig(baseURL: baseURL, model: "gpt-4o-mini", contextSize: 128_000)
    #expect(config.endpointURL?.absoluteString == "https://api.openai.com/v1/chat/completions")
}

@Test("a base URL that is not a URL yields no endpoint rather than a crash")
func endpointURLRejectsGarbage() {
    let config = RemoteConfig(baseURL: "not a url at all", model: "gpt-4o-mini", contextSize: 128_000)
    #expect(config.endpointURL == nil)
}
