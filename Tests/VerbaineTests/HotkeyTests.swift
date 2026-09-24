import Carbon.HIToolbox
import Foundation
import Testing
@testable import Verbaine

private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    UserDefaults(suiteName: name)!
}

@Test("an empty store yields the ⌃⌥P default")
func defaultHotkeyWhenUnset() {
    let hotkey = Hotkey.load(from: makeDefaults())
    #expect(hotkey == .standard)
    #expect(hotkey.keyCode == UInt32(kVK_ANSI_P))
    #expect(hotkey.modifiers == UInt32(controlKey | optionKey))
}

@Test("a saved hotkey round-trips through UserDefaults")
func hotkeyRoundTrip() {
    let defaults = makeDefaults()
    let saved = Hotkey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey))
    saved.save(to: defaults)
    #expect(Hotkey.load(from: defaults) == saved)
}

@Test("a half-written pair falls back to the default rather than a bogus key")
func partialStoreFallsBack() {
    let defaults = makeDefaults()
    defaults.set(Int(kVK_ANSI_G), forKey: "hotkey.keyCode")
    #expect(Hotkey.load(from: defaults) == .standard)
}
