import Testing
@testable import Verbaine

@MainActor
private func selection(_ text: String) -> Selection {
    Selection(text: text, bounds: nil, appBundleID: "com.apple.Notes", element: nil, source: .clipboard)
}

@MainActor
@Test("a fresh entry comes back with the original text")
func recordedEntryIsReturned() {
    let buffer = UndoBuffer()
    let start = ContinuousClock.Instant.now
    buffer.record(original: "teh cat", result: "the cat", selection: selection("teh cat"), at: start)

    let entry = buffer.take(at: start + .seconds(59))
    #expect(entry?.original == "teh cat")
    #expect(entry?.result == "the cat")
}

@MainActor
@Test("an entry past the 60 s window is dropped")
func expiredEntryIsDropped() {
    let buffer = UndoBuffer()
    let start = ContinuousClock.Instant.now
    buffer.record(original: "teh cat", result: "the cat", selection: selection("teh cat"), at: start)

    #expect(buffer.take(at: start + .seconds(61)) == nil)
}

@MainActor
@Test("taking an entry clears it, so one replace is undoable once")
func takeClearsTheSlot() {
    let buffer = UndoBuffer()
    let start = ContinuousClock.Instant.now
    buffer.record(original: "teh cat", result: "the cat", selection: selection("teh cat"), at: start)

    #expect(buffer.take(at: start) != nil)
    #expect(buffer.take(at: start) == nil)
}

@MainActor
@Test("recording again replaces the pending undo")
func recordOverwrites() {
    let buffer = UndoBuffer()
    let start = ContinuousClock.Instant.now
    buffer.record(original: "first", result: "First", selection: selection("first"), at: start)
    buffer.record(original: "second", result: "Second", selection: selection("second"), at: start)

    #expect(buffer.take(at: start)?.original == "second")
}

@MainActor
@Test("nothing recorded means nothing to undo")
func emptyBufferTakesNil() {
    #expect(UndoBuffer().take(at: .now) == nil)
}
