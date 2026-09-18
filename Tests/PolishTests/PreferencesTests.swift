import Carbon.HIToolbox
import Foundation
import Testing
@testable import Polish

/// A defaults domain of its own per test, so nothing touches the real preferences.
private func scratchDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "polish.tests.\(UUID().uuidString)")!
    return defaults
}

@Test("summary style falls back to bullets and round-trips")
func summaryStylePersists() {
    let defaults = scratchDefaults()
    #expect(Preferences.summaryStyle(defaults) == .bullets)

    defaults.set(SummaryStyle.paragraph.rawValue, forKey: Preferences.summaryStyleKey)
    #expect(Preferences.summaryStyle(defaults) == .paragraph)

    // A value written by an older or newer build must not crash the picker.
    defaults.set("haiku", forKey: Preferences.summaryStyleKey)
    #expect(Preferences.summaryStyle(defaults) == .bullets)
}

@Test("each summary style has its own instruction")
func summaryStylesDiffer() {
    #expect(Prompts.summarize(.bullets) != Prompts.summarize(.paragraph))
    #expect(Prompts.instructions(for: .summarize, summaryStyle: .paragraph) == Prompts.summarize(.paragraph))
}

@Test("fallback apps start at the defaults, then round-trip")
func fallbackAppsPersist() {
    let defaults = scratchDefaults()
    #expect(Preferences.fallbackApps(defaults) == Preferences.defaultFallbackApps)

    Preferences.setFallbackApps(["com.apple.Notes"], defaults)
    #expect(Preferences.fallbackApps(defaults) == ["com.apple.Notes"])
}

@Test("an emptied fallback list stays empty instead of reverting")
func emptyFallbackListPersists() {
    let defaults = scratchDefaults()
    Preferences.setFallbackApps([], defaults)
    #expect(Preferences.fallbackApps(defaults) == [])
}

@Test("saving the fallback list trims, drops blanks and de-duplicates")
func fallbackListIsCleaned() {
    let defaults = scratchDefaults()
    Preferences.setFallbackApps(["  com.apple.Notes ", "", "com.apple.Notes", "com.apple.mail"], defaults)
    #expect(Preferences.fallbackApps(defaults) == ["com.apple.Notes", "com.apple.mail"])
}

@MainActor
@Test("the fallback list drives which capture path an app takes")
func fallbackListDrivesCapturePath() {
    #expect(SelectionCapture.prefersClipboard(bundleID: "com.apple.Notes", fallbackApps: ["com.apple.Notes"]))
    #expect(!SelectionCapture.prefersClipboard(bundleID: "com.apple.Notes", fallbackApps: []))
}

@Test("hotkey round-trips through defaults and reads back as symbols")
func hotkeyPersists() {
    let defaults = scratchDefaults()
    #expect(Hotkey.load(from: defaults) == .standard)
    #expect(Hotkey.standard.displayString == "⌃⌥P")

    let custom = Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey))
    custom.save(to: defaults)
    #expect(Hotkey.load(from: defaults) == custom)
    #expect(custom.displayString == "⇧⌘K")
}

@Test("a shortcut needs control, option or command")
func hotkeyRequiresAModifier() {
    #expect(Hotkey.standard.hasRequiredModifier)
    #expect(!Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(shiftKey)).hasRequiredModifier)
    #expect(!Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: 0).hasRequiredModifier)
}
