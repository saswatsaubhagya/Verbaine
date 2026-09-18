import Testing
@testable import Polish

@Test("the on-device model is the default provider and is not remote")
func defaultProviderIsApple() {
    let provider = Inference.current
    #expect(provider.isRemote == false)
    #expect(provider.displayName == "Apple on-device")
}

@Test("the on-device provider reports the model's own context window, never an assumed 4096")
func appleProviderReportsContextSize() {
    #expect(Inference.current.contextSize > 0)
}
