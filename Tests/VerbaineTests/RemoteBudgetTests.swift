import Foundation
import Testing
@testable import Verbaine

private func provider(contextSize: Int = 128_000) -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(
        config: RemoteConfig(baseURL: "https://api.example.com/v1", model: "test-model", contextSize: contextSize),
        apiKey: "sk-test"
    )
}

@Test("the remote token count is a four-characters-per-token estimate")
func estimatesTokens() async throws {
    let text = String(repeating: "a", count: 400)
    #expect(try await provider().tokenCount(for: text) == 100)
}

@Test("an empty string costs nothing")
func estimatesEmpty() async throws {
    #expect(try await provider().tokenCount(for: "") == 0)
}

@Test("at a 128k window a long document is one pass, so chunking never fires")
func longTextIsSinglePass() async throws {
    // ~4,000 words of prose, far past anything the on-device model could take in one call.
    let text = String(repeating: "word ", count: 4_000)
    #expect(try await TokenBudget(service: provider()).fitsInOnePass(action: .improve, text: text))
}

@Test("a small declared window still chunks, so a local 8k model is not silently truncated")
func smallWindowStillChunks() async throws {
    let text = String(repeating: "word ", count: 4_000)
    #expect(try await TokenBudget(service: provider(contextSize: 8_000)).fitsInOnePass(action: .improve, text: text) == false)
}

@Test("a provider with no key says it is unconfigured, not that the Mac is unsupported")
func missingKeyIsUnconfigured() {
    let config = RemoteConfig(baseURL: "https://api.example.com/v1", model: "test-model", contextSize: 128_000)
    let provider = OpenAICompatibleProvider(config: config, apiKey: "")
    #expect(provider.availability == .remoteNotConfigured)
    #expect(UserFacingError(provider.availability)?.remedy == .modelSettings)
}

@Test("the remote provider announces itself as remote, by model name")
func remoteProviderIdentifiesItself() {
    #expect(provider().isRemote)
    #expect(provider().displayName == "test-model")
}
