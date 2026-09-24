import Foundation
import Testing
@testable import Verbaine

/// One token per word: deterministic, and close enough in shape to the real tokenizer that the
/// packing arithmetic is what the tests actually exercise.
private struct WordCounter: TokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

private let chunker = TextChunker(counter: WordCounter())

private func fixture(_ name: String) throws -> String {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

private func words(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}

// MARK: - Paragraph mode

@Test("the long fixture splits into its paragraphs, in order, with nothing blank")
func paragraphsFromFixture() throws {
    let paragraphs = TextChunker.paragraphs(try fixture("long-document.txt"))
    #expect(paragraphs.count == 40)
    #expect(paragraphs.first?.hasPrefix("Section 1.") == true)
    #expect(paragraphs.last?.hasPrefix("Section 40.") == true)
    #expect(paragraphs.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
}

@Test("runs of blank lines, trailing space and CRLF all read as one break")
func paragraphsTolerateMessyBreaks() {
    let text = "One.\r\n\r\n  \t \n\nTwo.\n\n\n\nThree.\n\n"
    #expect(TextChunker.paragraphs(text) == ["One.", "Two.", "Three."])
}

@Test("single-newline lines stay in the same paragraph")
func softWrapsAreNotParagraphBreaks() {
    #expect(TextChunker.paragraphs("first line\nsecond line") == ["first line\nsecond line"])
}

@Test("text with no paragraphs yields nothing")
func emptyParagraphs() {
    #expect(TextChunker.paragraphs("   \n\n  ").isEmpty)
}

// MARK: - Budgeted mode

@Test("no chunk exceeds the budget", arguments: ["long-document.txt", "chat-thread.txt"], [40, 120, 400])
func chunksStayInBudget(name: String, budget: Int) async throws {
    let chunks = try await chunker.budgeted(try fixture(name), maxTokens: budget)
    #expect(!chunks.isEmpty)
    #expect(chunks.allSatisfy { words($0) <= budget })
}

@Test("chunks are whole sentences, in order, with nothing dropped")
func chunksAreWholeSentences() async throws {
    let text = try fixture("long-document.txt")
    let chunks = try await chunker.budgeted(text, maxTokens: 120, overlapSentences: 0)
    let recombined = chunks.flatMap(TextChunker.sentences)
    #expect(recombined == TextChunker.sentences(text))
}

@Test("each chunk after the first repeats the tail of the one before it")
func overlapCarriesContext() async throws {
    let chunks = try await chunker.budgeted(try fixture("long-document.txt"), maxTokens: 120, overlapSentences: 1)
    #expect(chunks.count > 2)
    for (previous, next) in zip(chunks, chunks.dropFirst()) {
        let tail = TextChunker.sentences(previous).last
        let head = TextChunker.sentences(next).first
        #expect(tail == head)
    }
}

@Test("a two-sentence overlap repeats two sentences")
func overlapOfTwo() async throws {
    let chunks = try await chunker.budgeted(try fixture("long-document.txt"), maxTokens: 200, overlapSentences: 2)
    #expect(chunks.count > 2)
    for (previous, next) in zip(chunks, chunks.dropFirst()) {
        #expect(TextChunker.sentences(previous).suffix(2) == TextChunker.sentences(next).prefix(2))
    }
}

@Test("a sentence larger than the whole budget is split on word boundaries, not left over budget")
func oversizedSentenceIsSplit() async throws {
    let sentence = Array(repeating: "word", count: 500).joined(separator: " ") + "."
    let chunks = try await chunker.budgeted(sentence, maxTokens: 30)
    #expect(chunks.count >= 17)
    #expect(chunks.allSatisfy { words($0) <= 30 })
    #expect(chunks.joined(separator: " ").split(whereSeparator: \.isWhitespace).count == 500)
}

@Test("text that already fits comes back as one chunk")
func shortTextIsOneChunk() async throws {
    let chunks = try await chunker.budgeted("Hello there. How are you?", maxTokens: 2_500)
    #expect(chunks == ["Hello there. How are you?"])
}

@Test("empty input and a zero budget both yield no chunks", arguments: [("", 2_500), ("Some text.", 0)])
func nothingToChunk(text: String, budget: Int) async throws {
    let chunks = try await chunker.budgeted(text, maxTokens: budget)
    #expect(chunks.isEmpty)
}

@Test("abbreviations do not end a sentence")
func abbreviationsSurvive() {
    let sentences = TextChunker.sentences("Dr. Ruiz flagged the events table, i.e. the big one. We agreed.")
    #expect(sentences.count == 2)
    #expect(sentences.first?.contains("i.e.") == true)
}
