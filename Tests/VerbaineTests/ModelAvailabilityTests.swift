import FoundationModels
import Testing
@testable import Verbaine

@Test("every framework availability case maps to a user-facing case", arguments: [
    (SystemLanguageModel.Availability.available, ModelAvailability.ready),
    (.unavailable(.appleIntelligenceNotEnabled), .intelligenceDisabled),
    (.unavailable(.modelNotReady), .modelDownloading),
    (.unavailable(.deviceNotEligible), .unsupportedDevice),
])
func mapsAvailability(framework: SystemLanguageModel.Availability, expected: ModelAvailability) {
    #expect(ModelAvailability(framework) == expected)
}

@Test("context window is read from the model, never assumed to be 4096")
func contextSizeIsPositive() async throws {
    guard ModelService.shared.availability == .ready else { return }

    // See `appleProviderReportsContextSize`: a cold model reports 0 until a first call wakes it,
    // which made this test fail on the first run after boot and pass on the retry.
    _ = try? await ModelService.shared.tokenCount(for: "warm")
    #expect(ModelService.shared.contextSize > 0)
}
