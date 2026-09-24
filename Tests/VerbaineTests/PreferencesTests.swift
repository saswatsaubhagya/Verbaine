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

@Test("per-app tones start at the built-ins, then round-trip")
func defaultTonesPersist() {
    let defaults = scratchDefaults()
    #expect(Preferences.defaultTones(defaults) == Preferences.builtInDefaultTones)
    #expect(Preferences.defaultTone(forBundleID: "com.tinyspeck.slackmacgap", defaults) == .friendly)
    #expect(Preferences.defaultTone(forBundleID: "com.apple.mail", defaults) == .professional)
    #expect(Preferences.defaultTone(forBundleID: "com.linear", defaults) == .direct)

    Preferences.setDefaultTones(["com.apple.Notes": .apologetic], defaults)
    #expect(Preferences.defaultTones(defaults) == ["com.apple.Notes": .apologetic])
    #expect(Preferences.defaultTone(forBundleID: "com.apple.Notes", defaults) == .apologetic)
}

@Test("an unmapped or unknown app falls back to professional")
func unmappedAppUsesProfessional() {
    let defaults = scratchDefaults()
    #expect(Preferences.defaultTone(forBundleID: "com.apple.TextEdit", defaults) == .professional)
    #expect(Preferences.defaultTone(forBundleID: nil, defaults) == .professional)

    // A tone name written by an older or newer build must not crash the picker.
    defaults.set(["com.apple.Notes": "shakespearean"], forKey: Preferences.defaultTonesKey)
    #expect(Preferences.defaultTone(forBundleID: "com.apple.Notes", defaults) == .professional)
}

@Test("an emptied tone map stays empty instead of reverting")
func emptyToneMapPersists() {
    let defaults = scratchDefaults()
    Preferences.setDefaultTones([:], defaults)
    #expect(Preferences.defaultTones(defaults) == [:])
}

@Test("the tone menu lists the app's preset first and every tone once")
func tonesPreselectTheMappedTone() {
    let defaults = scratchDefaults()
    let slack = Preferences.tones(forBundleID: "com.tinyspeck.slackmacgap", defaults)
    #expect(slack.first == .friendly)
    #expect(Set(slack) == Set(Tone.allCases))
    #expect(slack.count == Tone.allCases.count)
    #expect(Preferences.tones(forBundleID: nil, defaults).first == .professional)
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

@Test("built-in action hotkeys start at the defaults, then round-trip")
func actionHotkeysPersist() {
    let defaults = scratchDefaults()
    #expect(Preferences.actionHotkeys(defaults) == Preferences.builtInActionHotkeys)
    #expect(Preferences.actionHotkeys(defaults)[Action.fixGrammar.id]?.displayString == "⌃⌥G")

    let custom = Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
    Preferences.setActionHotkeys([Action.improve.id: custom], defaults)
    #expect(Preferences.actionHotkeys(defaults) == [Action.improve.id: custom])
}

@Test("clearing every action hotkey stays cleared instead of reverting")
func actionHotkeysStayCleared() {
    let defaults = scratchDefaults()
    Preferences.setActionHotkeys([:], defaults)
    #expect(Preferences.actionHotkeys(defaults).isEmpty)
    #expect(Preferences.hotkeyedActions(defaults).isEmpty)
}

@Test("hotkeyed actions cover the built-in grid and the user's own")
func hotkeyedActionsCombineBothLists() {
    let defaults = scratchDefaults()
    let custom = CustomAction(
        name: "Release note",
        instruction: "Rewrite as a release note.",
        hotkey: Hotkey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey))
    )
    Preferences.setCustomActions([custom, CustomAction(name: "No shortcut", instruction: "x")], defaults)

    let entries = Preferences.hotkeyedActions(defaults)
    #expect(entries.map(\.action) == [.fixGrammar, .custom(custom)])
    #expect(entries.last?.hotkey == custom.hotkey)
}

@Test("a stored id maps back to its built-in action, and custom ids do not")
func actionsRebuildFromID() {
    #expect(Action(id: Action.fixGrammar.id) == .fixGrammar)
    #expect(Action(id: Action.changeTone(.friendly).id) == .changeTone(.friendly))
    #expect(Action(id: "custom.\(UUID().uuidString)") == nil)
    #expect(Action(id: "haiku") == nil)
}
