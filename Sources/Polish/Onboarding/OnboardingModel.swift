import Foundation
import Observation

/// Drives the onboarding window: which step is showing, what the world looks like right now,
/// and what the Accessibility step's Test button found.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep = .welcome
    private(set) var availability: ModelAvailability = .unsupportedDevice
    private(set) var isTrusted: Bool = false
    private(set) var test: TestResult?

    /// What the Test button got back: the selection it read, or why it read nothing.
    enum TestResult: Equatable {
        case captured(String)
        case failed(String)
    }

    /// Set by the window so Finish can close it.
    var onFinish: () -> Void = {}

    init() {
        refresh()
    }

    /// Re-reads the two permissions. Called on a timer while the window is open, because the
    /// user grants both in System Settings and nothing notifies us when they do.
    func refresh() {
        availability = ModelService.shared.availability
        isTrusted = AccessibilityPermission.isTrusted
    }

    var canContinue: Bool {
        step.isSatisfied(availability: availability, isTrusted: isTrusted)
    }

    func back() {
        guard let previous = step.previous else { return }
        step = previous
    }

    /// Moves on, or finishes when there is nowhere left to move.
    func advance() {
        guard canContinue else { return }
        guard let next = step.next else {
            OnboardingFlag.markComplete()
            onFinish()
            return
        }
        step = next
    }

    /// Reads whatever is selected in the frontmost app, the same way the hotkey does. The
    /// onboarding window is a non-activating panel, so the user's app is still frontmost here.
    func runTest() async {
        do {
            let selection = try await SelectionCapture.capture()
            test = .captured(selection.text)
        } catch {
            test = .failed(UserFacingError(error).message)
        }
        refresh()
    }
}
