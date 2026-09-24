import Testing
@testable import Verbaine

@Test("the on-device model is the default provider and is not remote")
func defaultProviderIsApple() {
    let provider = Inference.current
    #expect(provider.isRemote == false)
    #expect(provider.displayName == "Apple on-device")
}

@Test("the on-device provider reports the model's own context window, never an assumed 4096")
func appleProviderReportsContextSize() async throws {
    let provider = Inference.current
    guard provider.availability == .ready else { return }

    // A cold model reports contextSize 0 until something forces it to initialise, so this test
    // used to fail on the first run after boot and pass on the retry. Measuring one token is the
    // cheapest way to make the model real before asking it how big its window is.
    _ = try? await provider.tokenCount(for: "warm")
    #expect(provider.contextSize > 0)
}
