import AppKit
import FoundationModels

/// Every failure the user can see, as one sentence plus the one thing they can do about it.
///
/// Errors arrive from three places — capture, the model, write-back — in three unrelated
/// vocabularies, two of which are Apple's and change between OS versions. Mapping them here
/// keeps `localizedDescription` ("The operation couldn’t be completed") out of the popover.
struct UserFacingError: Error, Equatable {
    /// The single button the message gets. `dismiss` means nothing can be done but close.
    enum Remedy: Equatable {
        /// Run the same action again — transient failures and over-long selections.
        case retry
        /// The model produced nothing usable, so the only thing worth having is the input back.
        case copyOriginal
        /// A result exists but could not be pasted; hand it over via the clipboard instead.
        case copyResult
        case accessibilitySettings
        case intelligenceSettings
        case dismiss
    }

    let message: String
    let remedy: Remedy

    /// Maps a thrown error. Unknown errors become a generic retry rather than a raw
    /// `localizedDescription`, and are logged by the caller.
    init(_ error: any Error) {
        switch error {
        case let error as UserFacingError:
            self = error
        case let error as CaptureError:
            self = UserFacingError(error)
        case let error as WriteBackError:
            self = UserFacingError(error)
        default:
            self = Self.model(error) ?? UserFacingError(
                message: "Something went wrong. Try that again.",
                remedy: .retry
            )
        }
    }

    init(message: String, remedy: Remedy) {
        self.message = message
        self.remedy = remedy
    }

    init(_ error: CaptureError) {
        switch error {
        case .accessibilityNotTrusted:
            self.init(
                message: "Polish needs Accessibility permission to read the text you select.",
                remedy: .accessibilitySettings
            )
        case .noFrontmostApp, .noFocusedElement:
            self.init(
                message: "Click into the text you want to polish, then press the hotkey again.",
                remedy: .dismiss
            )
        case .emptySelection:
            self.init(
                message: "Select some text first, then press the hotkey again.",
                remedy: .dismiss
            )
        case .clipboardCopyTimedOut:
            self.init(
                message: "This app did not hand over the selected text. Select it again and retry.",
                remedy: .dismiss
            )
        }
    }

    init(_ error: WriteBackError) {
        switch error {
        case .accessibilityNotTrusted:
            self.init(
                message: "Polish needs Accessibility permission to paste the result back.",
                remedy: .accessibilitySettings
            )
        case .sourceAppGone:
            self.init(
                message: "The app this text came from has quit. Nothing was pasted.",
                remedy: .copyResult
            )
        case .focusChanged:
            self.init(
                message: "The cursor moved somewhere else, so nothing was pasted.",
                remedy: .copyResult
            )
        }
    }

    /// The reason the model will not answer at all. `nil` when it is ready.
    init?(_ availability: ModelAvailability) {
        switch availability {
        case .ready:
            return nil
        case .intelligenceDisabled:
            self.init(
                message: "Turn on Apple Intelligence in System Settings to use Polish.",
                remedy: .intelligenceSettings
            )
        case .modelDownloading:
            self.init(
                message: "Apple Intelligence is still downloading its model. Try again shortly.",
                remedy: .dismiss
            )
        case .unsupportedDevice:
            self.init(
                message: "This Mac cannot run Apple Intelligence, so Polish cannot rewrite text.",
                remedy: .dismiss
            )
        }
    }

    /// Both of the framework's error vocabularies: `GenerationError` is what macOS 26 throws,
    /// `LanguageModelError` what macOS 27 throws for the same conditions. `nil` if the error is
    /// neither.
    private static func model(_ error: any Error) -> UserFacingError? {
        if #available(macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded:
                return tooLong
            case .guardrailViolation, .refusal:
                return declined
            case .rateLimited, .timeout:
                return busy
            case .unsupportedLanguageOrLocale:
                return unsupportedLanguage
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
                return confused
            @unknown default:
                return confused
            }
        }

        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return tooLong
            case .guardrailViolation, .refusal:
                return declined
            case .rateLimited, .concurrentRequests:
                return busy
            case .unsupportedLanguageOrLocale:
                return unsupportedLanguage
            case .assetsUnavailable:
                return UserFacingError(
                    message: "Apple Intelligence is still downloading its model. Try again shortly.",
                    remedy: .dismiss
                )
            case .decodingFailure, .unsupportedGuide:
                return confused
            @unknown default:
                return confused
            }
        }

        return nil
    }

    // The selection is over budget. Phase 2 chunks it; until then retrying a shorter selection
    // is the whole remedy, and the message says so rather than truncating silently.
    private static let tooLong = UserFacingError(
        message: "This selection is too long to rewrite in one pass. Select less and retry.",
        remedy: .retry
    )
    private static let declined = UserFacingError(
        message: "The on-device model declined to rewrite this text.",
        remedy: .copyOriginal
    )
    private static let busy = UserFacingError(
        message: "The model is busy. Try that again in a moment.",
        remedy: .retry
    )
    private static let unsupportedLanguage = UserFacingError(
        message: "The on-device model does not handle this language yet.",
        remedy: .copyOriginal
    )
    private static let confused = UserFacingError(
        message: "The model could not finish this rewrite.",
        remedy: .retry
    )
}

extension UserFacingError.Remedy {
    /// Button title, or `nil` for `dismiss` — that one gets a plain Close.
    var title: String? {
        switch self {
        case .retry: "Retry"
        case .copyOriginal: "Copy original"
        case .copyResult: "Copy result"
        case .accessibilitySettings: "Open Settings"
        case .intelligenceSettings: "Open Settings"
        case .dismiss: nil
        }
    }
}

/// Opens the System Settings panes the remedies point at.
enum SettingsPane {
    static func openAppleIntelligence() {
        // ponytail: same deal as the Accessibility pane — no API, stable URL, fails soft by
        // opening Settings at the top.
        open("x-apple.systempreferences:com.apple.Siri-Settings.extension")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
