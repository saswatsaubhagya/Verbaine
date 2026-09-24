import Foundation

/// The three first-launch steps, in order: what Polish is, then the two things it cannot work
/// without — Apple Intelligence and Accessibility.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case intelligence
    case accessibility

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    var title: String {
        switch self {
        case .welcome: "Polish rewrites the text you select"
        case .intelligence: "Turn on Apple Intelligence"
        case .accessibility: "Let Polish read your selection"
        }
    }

    /// Whether the step's requirement is met right now, so the user can move on.
    ///
    /// `unsupportedDevice` counts as satisfied: there is nothing the user can flip, and holding
    /// them on a step they cannot pass would trap them in onboarding forever.
    func isSatisfied(availability: ModelAvailability, isTrusted: Bool) -> Bool {
        switch self {
        case .welcome:
            return true
        case .intelligence:
            return availability == .ready || availability == .unsupportedDevice
        case .accessibility:
            return isTrusted
        }
    }
}

/// Whether first-launch onboarding has been completed, in `UserDefaults`.
enum OnboardingFlag {
    private static let key = "onboarding.completed"

    static func isComplete(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markComplete(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key)
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
