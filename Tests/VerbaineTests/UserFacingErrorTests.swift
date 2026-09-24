import Foundation
import FoundationModels
import Testing
@testable import Verbaine

@Test("capture errors get their own sentence and remedy", arguments: [
    (CaptureError.accessibilityNotTrusted, UserFacingError.Remedy.accessibilitySettings),
    (.noFrontmostApp, .dismiss),
    (.noFocusedElement, .dismiss),
    (.emptySelection, .dismiss),
    (.clipboardCopyTimedOut, .dismiss),
])
func mapsCaptureErrors(error: CaptureError, expected: UserFacingError.Remedy) {
    let mapped = UserFacingError(error as any Error)
    #expect(mapped.remedy == expected)
    #expect(mapped == UserFacingError(error))
}

@Test("write-back errors offer the clipboard, not a lost result", arguments: [
    (WriteBackError.accessibilityNotTrusted, UserFacingError.Remedy.accessibilitySettings),
    (.sourceAppGone, .copyResult),
    (.focusChanged, .copyResult),
])
func mapsWriteBackErrors(error: WriteBackError, expected: UserFacingError.Remedy) {
    #expect(UserFacingError(error as any Error).remedy == expected)
}

@Test("a guardrail violation offers Copy original and nothing else")
func guardrailOffersCopyOriginalOnly() {
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
    let mapped = UserFacingError(LanguageModelSession.GenerationError.guardrailViolation(context))

    #expect(mapped.remedy == .copyOriginal)
    #expect(mapped.remedy.title == "Copy original")
}

@Test("an over-long selection says so instead of truncating")
func contextExceededSaysSelectLess() {
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
    let mapped = UserFacingError(LanguageModelSession.GenerationError.exceededContextWindowSize(context))

    #expect(mapped.remedy == .retry)
    #expect(mapped.message.contains("too long"))
}

@available(macOS 27.0, *)
@Test("the macOS 27 error family maps to the same messages as the 26 one")
func newErrorFamilyMatchesOld() {
    let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")

    #expect(
        UserFacingError(LanguageModelError.contextSizeExceeded(
            .init(contextSize: 4096, tokenCount: 9001, debugDescription: "test")
        ))
        == UserFacingError(LanguageModelSession.GenerationError.exceededContextWindowSize(context))
    )
    #expect(
        UserFacingError(LanguageModelError.guardrailViolation(.init(debugDescription: "test")))
        == UserFacingError(LanguageModelSession.GenerationError.guardrailViolation(context))
    )
}

@Test("an unavailable model is an error before the action runs", arguments: [
    (ModelAvailability.intelligenceDisabled, UserFacingError.Remedy.intelligenceSettings),
    (.modelDownloading, .dismiss),
    (.unsupportedDevice, .dismiss),
])
func mapsUnavailability(availability: ModelAvailability, expected: UserFacingError.Remedy) {
    #expect(UserFacingError(availability)?.remedy == expected)
}

@Test("a ready model is not an error")
func readyIsNotAnError() {
    #expect(UserFacingError(ModelAvailability.ready) == nil)
}

@Test("an unrecognised error becomes a retry, never a framework string")
func unknownErrorIsGeneric() {
    let mapped = UserFacingError(CocoaError(.fileNoSuchFile))

    #expect(mapped.remedy == .retry)
    #expect(!mapped.message.contains("Cocoa"))
}

@Test("mapping is idempotent, so a UserFacingError can be rethrown")
func mappingIsIdempotent() {
    let mapped = UserFacingError(CaptureError.emptySelection)
    #expect(UserFacingError(mapped as any Error) == mapped)
}

@Test("every error the debug menu can trigger has a message")
func debugSamplesAllMap() {
    for sample in DebugErrors.all {
        #expect(!UserFacingError(sample.error).message.isEmpty, "\(sample.name)")
    }
    for sample in DebugErrors.unavailable {
        #expect(UserFacingError(sample.availability) != nil, "\(sample.name)")
    }
}
