import Testing
@testable import Verbaine

private func words(_ text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map(String.init)
}

private func text(_ segments: [DiffEngine.Segment], _ kinds: Set<DiffEngine.Kind>) -> String {
    segments.filter { kinds.contains($0.kind) }.map(\.text).joined()
}

@Test("tokens carry their trailing whitespace, so joining them rebuilds the input")
func tokenizeRoundTrips() {
    let original = "Hi  there,\nhow are you? "
    #expect(DiffEngine.tokenize(original).joined() == original)
}

@Test("identical text is all unchanged")
func noEdits() {
    let segments = DiffEngine.diff(original: "I have an apple", result: "I have an apple")
    #expect(segments.allSatisfy { $0.kind == .same })
}

@Test("a substituted word shows as one removal and one insertion")
func substitution() {
    let segments = DiffEngine.diff(original: "I has a apple", result: "I have an apple")
    #expect(segments.filter { $0.kind == .removed }.map(\.text) == ["has ", "a "])
    #expect(segments.filter { $0.kind == .inserted }.map(\.text) == ["have ", "an "])
}

@Test("the unchanged words survive in both panes")
func panesRebuildBothSides() {
    let original = "the quick brown fox"
    let result = "the slow brown fox jumps"
    let segments = DiffEngine.diff(original: original, result: result)
    // The result pane rebuilds the rewrite exactly; the original pane rebuilds the original up to
    // the whitespace around unchanged words, which comes from the result side (see `diff`).
    #expect(text(segments, [.same, .inserted]) == result)
    #expect(words(text(segments, [.same, .removed])) == words(original))
}

@Test("an empty result is all removals")
func emptyResult() {
    let segments = DiffEngine.diff(original: "one two", result: "")
    #expect(segments.allSatisfy { $0.kind == .removed })
    #expect(text(segments, [.removed]) == "one two")
}

@Test("an empty original is all insertions")
func emptyOriginal() {
    let segments = DiffEngine.diff(original: "", result: "one two")
    #expect(segments.allSatisfy { $0.kind == .inserted })
}

@Test("whitespace-only changes do not read as edits")
func whitespaceIgnored() {
    let segments = DiffEngine.diff(original: "one two", result: "one  two")
    #expect(segments.allSatisfy { $0.kind == .same })
}
