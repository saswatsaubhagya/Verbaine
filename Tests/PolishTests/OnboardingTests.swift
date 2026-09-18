import Foundation
import Testing
@testable import Polish

private func scratchDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    UserDefaults(suiteName: name)!
}

@Test("the welcome step never blocks")
func welcomeAlwaysSatisfied() {
    #expect(OnboardingStep.welcome.isSatisfied(availability: .intelligenceDisabled, isTrusted: false))
}

@Test("the Apple Intelligence step blocks only on states the user can fix")
func intelligenceGating() {
    let step = OnboardingStep.intelligence
    #expect(step.isSatisfied(availability: .ready, isTrusted: false))
    #expect(!step.isSatisfied(availability: .intelligenceDisabled, isTrusted: true))
    #expect(!step.isSatisfied(availability: .modelDownloading, isTrusted: true))
    // Nothing to flip on an ineligible Mac — blocking here would trap the user in onboarding.
    #expect(step.isSatisfied(availability: .unsupportedDevice, isTrusted: false))
}

@Test("the Accessibility step needs the permission")
func accessibilityGating() {
    let step = OnboardingStep.accessibility
    #expect(step.isSatisfied(availability: .ready, isTrusted: true))
    #expect(!step.isSatisfied(availability: .ready, isTrusted: false))
}

@Test("the steps run welcome → intelligence → accessibility and stop")
func stepOrder() {
    #expect(OnboardingStep.welcome.next == .intelligence)
    #expect(OnboardingStep.intelligence.next == .accessibility)
    #expect(OnboardingStep.accessibility.next == nil)
    #expect(OnboardingStep.welcome.previous == nil)
    #expect(OnboardingStep.accessibility.previous == .intelligence)
}

@Test("the completion flag is off until marked and clears on reset")
func completionFlag() {
    let defaults = scratchDefaults()
    #expect(!OnboardingFlag.isComplete(defaults))

    OnboardingFlag.markComplete(defaults)
    #expect(OnboardingFlag.isComplete(defaults))

    OnboardingFlag.reset(defaults)
    #expect(!OnboardingFlag.isComplete(defaults))
}
