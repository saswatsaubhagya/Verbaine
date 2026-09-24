import Foundation
import Testing
@testable import Verbaine

private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "verbaine.tests.\(UUID().uuidString)")!
}

private let releaseNote = CustomAction(
    name: "Rewrite as release note",
    instruction: "Rewrite the user's text as a one-paragraph release note for end users.",
    defaultButton: .copy,
    hotkey: Hotkey.standard
)

@Test("custom actions start empty and round-trip, hotkey included")
func customActionsPersist() {
    let defaults = scratchDefaults()
    #expect(Preferences.customActions(defaults).isEmpty)

    Preferences.setCustomActions([releaseNote], defaults)
    let loaded = Preferences.customActions(defaults)
    #expect(loaded == [releaseNote])
    #expect(loaded.first?.hotkey == .standard)
}

@Test("a garbled store reads as no custom actions rather than crashing")
func corruptStoreIsEmpty() {
    let defaults = scratchDefaults()
    defaults.set(Data("not json".utf8), forKey: Preferences.customActionsKey)
    #expect(Preferences.customActions(defaults).isEmpty)
}

@Test("a custom action's instruction is its own wording plus the output-only rule")
func customInstruction() {
    let instruction = Action.custom(releaseNote).instructions
    #expect(instruction.contains("release note for end users."))
    #expect(instruction.contains("no preamble"))
}

@Test("custom actions follow the built-ins in the grid and keep their identity")
func customActionsAppendToGrid() {
    let grid = Action.grid(customActions: [releaseNote])
    #expect(grid.count == Action.grid.count + 1)
    #expect(grid.last == .custom(releaseNote))
    #expect(grid.last?.title == "Rewrite as release note")
    #expect(grid.last?.id == "custom.\(releaseNote.id.uuidString)")
    // Sized as a rewrite: the output reserve has to assume the result is as long as the input.
    #expect(grid.last?.isRewrite == true)
}

@Test("the default button is the action's own choice, and Replace for built-ins")
func defaultButtonFollowsTheAction() {
    #expect(Action.custom(releaseNote).defaultButton == .copy)
    #expect(Action.improve.defaultButton == .replace)
}

@Test("validation rejects a blank name, a blank instruction and an over-long one")
func validation() {
    #expect(CustomAction.validationError(name: " ", instruction: "Do a thing.", tokens: 4) != nil)
    #expect(CustomAction.validationError(name: "Note", instruction: "  ", tokens: 0) != nil)
    #expect(CustomAction.validationError(name: "Note", instruction: "Do a thing.", tokens: 301) != nil)
    #expect(CustomAction.validationError(name: "Note", instruction: "Do a thing.", tokens: 300) == nil)
}

@Test("an unmeasurable instruction still gets a token estimate")
func tokenCountFallsBack() async {
    let tokens = await CustomAction.tokenCount(of: String(repeating: "a", count: 40))
    #expect(tokens > 0)
    #expect(tokens <= 40)
}
