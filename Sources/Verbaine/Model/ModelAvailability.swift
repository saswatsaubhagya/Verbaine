import FoundationModels

/// Why the on-device model can or cannot be used right now, in terms the UI can speak.
///
/// `SystemLanguageModel.Availability` is the framework's vocabulary; this is ours. Onboarding
/// (T1.7) and `UserFacingError` (T1.6) both switch over this, so every framework case has to
/// land on exactly one of these four.
enum ModelAvailability: Equatable, Sendable {
    /// The model is loaded and will answer.
    case ready
    /// Apple Intelligence is off in System Settings. The user can fix this.
    case intelligenceDisabled
    /// Apple Intelligence is on but the assets are still downloading. Waiting fixes this.
    case modelDownloading
    /// This Mac cannot run the model at all. Nothing fixes this.
    case unsupportedDevice
    /// A custom endpoint is selected but its URL, model name or key is missing. Only a remote
    /// provider ever reports this; `init(_:)` below never produces it, because the framework has
    /// no such concept.
    case remoteNotConfigured

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            self = .intelligenceDisabled
        case .unavailable(.modelNotReady):
            self = .modelDownloading
        case .unavailable(.deviceNotEligible):
            self = .unsupportedDevice
        case .unavailable:
            // UnavailableReason is not frozen. A reason added in a later macOS is still a
            // hard stop, and "this Mac can't run it" is the only bucket that never invites
            // the user to fix something they cannot fix.
            self = .unsupportedDevice
        }
    }
}
