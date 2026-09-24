import Foundation
import FoundationModels
import Testing
@testable import Verbaine

/// One token per word, as elsewhere in these tests.
private struct WordCounter: TokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Throws a context-size error on the calls named in `failing` (1-based), echoes the prompt
/// otherwise, so the halves show up in the stitched result.
private actor FlakyGenerator: TextGenerating {
    private(set) var prompts: [String] = []
    private let failing: Set<Int>
    private let error: any Error

    init(failing: Set<Int>, error: any Error = contextError()) {
        self.failing = failing
        self.error = error
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        prompts.append(prompt)
        if failing.contains(prompts.count) { throw error }
        return prompt
    }

    func seen() -> [String] { prompts }
}

private func contextError() -> any Error {
    LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "test"))
}

private enum StubError: Error { case boom }

private func counterPair() -> (TokenBudget, TextChunker) {
    let counter = WordCounter()
    return (TokenBudget(contextSize: 4096, counter: counter), TextChunker(counter: counter))
}

// MARK: - Splitting

@Test("halving splits on a sentence boundary")
func halveSplitsOnSentences() throws {
    let halves = try #require(ContextRetry.halve("One two. Three four. Five six. Seven eight."))

    #expect(halves.0 == "One two. Three four.")
    #expect(halves.1 == "Five six. Seven eight.")
}

@Test("a single sentence halves on words, and one word cannot be halved")
func halveFallsBackToWords() throws {
    let halves = try #require(ContextRetry.halve("alpha beta gamma delta"))

    #expect(halves.0 == "alpha beta")
    #expect(halves.1 == "gamma delta")
    #expect(ContextRetry.halve("alpha") == nil)
}

// MARK: - Rewrite

@Test("a rewrite that hits a context error retries once with halves")
func rewriteRetriesHalves() async throws {
    let generator = FlakyGenerator(failing: [1])
    let (budget, chunker) = counterPair()
    let rewriter = ParagraphRewriter(generator: generator, budget: budget, chunker: chunker)

    let result = try await rewriter.run("One two. Three four.", action: .fixGrammar) { _ in }

    let seen = await generator.seen()
    #expect(result == "One two. Three four.")
    #expect(seen == ["One two. Three four.", "One two.", "Three four."])
}

@Test("a non-context error is not retried")
func rewriteDoesNotRetryOtherErrors() async throws {
    let generator = FlakyGenerator(failing: [1], error: StubError.boom)
    let (budget, chunker) = counterPair()
    let rewriter = ParagraphRewriter(generator: generator, budget: budget, chunker: chunker)

    await #expect(throws: StubError.self) {
        try await rewriter.run("One two. Three four.", action: .fixGrammar) { _ in }
    }
    let seen = await generator.seen()
    #expect(seen.count == 1)
}

@Test("a half that still does not fit surfaces the error")
func rewriteGivesUpAfterOneRetry() async throws {
    let generator = FlakyGenerator(failing: [1, 2])
    let (budget, chunker) = counterPair()
    let rewriter = ParagraphRewriter(generator: generator, budget: budget, chunker: chunker)

    await #expect(throws: (any Error).self) {
        try await rewriter.run("One two. Three four.", action: .fixGrammar) { _ in }
    }
    let seen = await generator.seen()
    #expect(seen.count == 2)
}

// MARK: - Summarize

@Test("a summarize chunk that hits a context error retries once with halves")
func summarizeRetriesHalves() async throws {
    let generator = FlakyGenerator(failing: [1])
    let (budget, chunker) = counterPair()
    let summarizer = MapReduceSummarizer(generator: generator, budget: budget, chunker: chunker)

    _ = try await summarizer.run("One two. Three four.") { _ in }

    let seen = await generator.seen()
    // The failed map call, its two halves, then the reduce.
    #expect(seen.count == 4)
    #expect(seen[1] == "One two.")
    #expect(seen[2] == "Three four.")
}
