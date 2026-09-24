#if DEBUG
import Foundation
import FoundationModels

/// Every failure T1.6 maps, as a thing that can be thrown on demand.
///
/// The debug menu shows each one through the same `UserFacingError(_:)` path the real failures
/// take, so "shows the right message" is checkable without provoking a guardrail or quitting
/// Slack mid-rewrite.
enum DebugErrors {
    /// Named samples, in the order the task lists them.
    static var all: [(name: String, error: any Error)] {
        var samples: [(name: String, error: any Error)] = [
            ("Capture: not trusted", CaptureError.accessibilityNotTrusted),
            ("Capture: no focused element", CaptureError.noFocusedElement),
            ("Capture: empty selection", CaptureError.emptySelection),
            ("Capture: ⌘C timed out", CaptureError.clipboardCopyTimedOut),
            ("Write-back: source app gone", WriteBackError.sourceAppGone),
            ("Write-back: focus changed", WriteBackError.focusChanged),
        ]

        let context = LanguageModelSession.GenerationError.Context(debugDescription: "debug menu")
        samples += [
            ("Model: context exceeded", LanguageModelSession.GenerationError.exceededContextWindowSize(context)),
            ("Model: guardrail violation", LanguageModelSession.GenerationError.guardrailViolation(context)),
            ("Model: rate limited", LanguageModelSession.GenerationError.rateLimited(context)),
            ("Model: assets unavailable", LanguageModelSession.GenerationError.assetsUnavailable(context)),
        ]

        // macOS 27 throws these instead of the `GenerationError` equivalents above, so both
        // families need a menu entry on a machine that can produce both.
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            samples += [
                ("Model 27: context exceeded", LanguageModelError.contextSizeExceeded(
                    .init(contextSize: 4096, tokenCount: 9001, debugDescription: "debug menu")
                )),
                ("Model 27: guardrail violation", LanguageModelError.guardrailViolation(
                    .init(debugDescription: "debug menu")
                )),
                ("Model 27: unsupported language", LanguageModelError.unsupportedLanguageOrLocale(
                    .init(languageCode: .kannada, debugDescription: "debug menu")
                )),
                ("Model 27: timeout", LanguageModelError.timeout(.init(debugDescription: "debug menu"))),
            ]
        }
        #endif

        samples.append(("Unknown error", CocoaError(.fileNoSuchFile)))
        return samples
    }

    /// The availability failures, which are not thrown — the popover checks for them up front.
    static let unavailable: [(name: String, availability: ModelAvailability)] = [
        ("Model off: Intelligence disabled", .intelligenceDisabled),
        ("Model off: downloading", .modelDownloading),
        ("Model off: unsupported Mac", .unsupportedDevice),
        ("Remote not configured", .remoteNotConfigured),
    ]
}
#endif
