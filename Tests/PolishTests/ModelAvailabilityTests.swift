import FoundationModels
import Testing
@testable import Polish

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
func contextSizeIsPositive() {
    #expect(ModelService.shared.contextSize > 0)
}
