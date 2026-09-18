import Foundation
import Testing
@testable import Polish

/// One token per word, as in `TextChunkerTests`: deterministic, and the packing arithmetic stays
/// the only variable.
private struct WordCounter: TokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Records every prompt it is asked and answers with a marked-up copy, so the stitched result
/// shows which part came from where.
private actor RecordingGenerator: TextGenerating {
    private(set) var prompts: [String] = []
    private let transform: @Sendable (String) -> String
    private let failAt: Int?

    init(failAt: Int? = nil, transform: @escaping @Sendable (String) -> String = { "[\($0)]" }) {
        self.failAt = failAt
        self.transform = transform
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        prompts.append(prompt)
        if prompts.count == failAt { throw StubError.boom }
        return transform(prompt)
    }

    func seen() -> [String] { prompts }
}

private enum StubError: Error { case boom }

private func rewriter(
    generator: any TextGenerating,
    contextSize: Int = 4096,
    instructions: Int = 100
) -> ParagraphRewriter {
    let counter = WordCounter()
    return ParagraphRewriter(
        generator: generator,
        budget: TokenBudget(contextSize: contextSize, counter: counter),
        chunker: TextChunker(counter: counter)
    )
}

private func fixture(_ name: String) throws -> String {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - Splitting

@Test("a long document splits into exactly its paragraphs when each one fits")
func partsAreParagraphs() async throws {
    let text = try fixture("long-document.txt")
    let parts = try await rewriter(generator: RecordingGenerator()).parts(of: text, action: .fixGrammar)
    #expect(parts == TextChunker.paragraphs(text))
}

@Test("a paragraph larger than one call is split further, never dropped")
func oversizedParagraphIsSplit() async throws {
    // 1,000-word paragraph against a tiny window: the budget is far below it.
    let paragraph = Array(repeating: "word", count: 1_000).joined(separator: " ") + "."
    let text = "Short opener.\n\n\(paragraph)\n\nShort closer."
    let parts = try await rewriter(generator: RecordingGenerator(), contextSize: 800)
        .parts(of: text, action: .fixGrammar)

    #expect(parts.count > 3)
    #expect(parts.first == "Short opener.")
    #expect(parts.last == "Short closer.")
    // Nothing is lost: every word of the big paragraph survives across the parts.
    let rejoined = parts.dropFirst().dropLast().joined(separator: " ")
    #expect(rejoined.split(whereSeparator: \.isWhitespace).count == 1_000)
}

@Test("no part exceeds the single-pass budget")
func partsFitTheBudget() async throws {
    let text = try fixture("long-document.txt")
    let budget = TokenBudget(contextSize: 900, counter: WordCounter())
    let limit = try await budget.maxSinglePassInputTokens(for: .improve)
    let parts = try await rewriter(generator: RecordingGenerator(), contextSize: 900)
        .parts(of: text, action: .improve)

    for part in parts {
        #expect(part.split(whereSeparator: \.isWhitespace).count <= limit)
    }
}

@Test("instructions that leave no room produce no parts rather than a negative budget")
func noBudgetNoParts() async throws {
    let parts = try await rewriter(generator: RecordingGenerator(), contextSize: 100, instructions: 100)
        .parts(of: "Anything at all.", action: .fixGrammar)
    #expect(parts.isEmpty)
}

// MARK: - Running

/// Collects every progress step a run emits.
private func collect(
    _ rewriter: ParagraphRewriter,
    _ text: String,
    _ action: Action,
    stoppingAfter limit: Int? = nil
) async throws -> [ParagraphRewriter.Progress] {
    let box = Steps()
    try await rewriter.run(text, action: action) { step in
        await box.append(step)
        if let limit, await box.count() >= limit { withUnsafeCurrentTask { $0?.cancel() } }
    }
    return await box.all()
}

private actor Steps {
    private var steps: [ParagraphRewriter.Progress] = []
    func append(_ step: ParagraphRewriter.Progress) { steps.append(step) }
    func count() -> Int { steps.count }
    func all() -> [ParagraphRewriter.Progress] { steps }
}

@Test("parts run in order, one session each, and stitch back with blank lines")
func stitchesInOrder() async throws {
    let generator = RecordingGenerator()
    let text = "First para.\n\nSecond para.\n\nThird para."
    let steps = try await collect(rewriter(generator: generator), text, .fixGrammar)

    #expect(await generator.seen() == ["First para.", "Second para.", "Third para."])
    #expect(steps.map(\.part) == [1, 2, 3])
    #expect(steps.allSatisfy { $0.total == 3 })
    #expect(steps.last?.text == "[First para.]\n\n[Second para.]\n\n[Third para.]")
}

@Test("each step carries the whole result so far, so the pane grows a paragraph at a time")
func progressIsCumulative() async throws {
    let steps = try await collect(rewriter(generator: RecordingGenerator()), "One.\n\nTwo.\n\nThree.", .improve)
    #expect(steps.map(\.text) == ["[One.]", "[One.]\n\n[Two.]", "[One.]\n\n[Two.]\n\n[Three.]"])
}

@Test("the return value is the stitched rewrite")
func returnsStitchedResult() async throws {
    let result = try await rewriter(generator: RecordingGenerator()).run("A.\n\nB.", action: .fixGrammar) { _ in }
    #expect(result == "[A.]\n\n[B.]")
}

@Test("model output is trimmed so stray newlines do not multiply the blank lines")
func trimsEachPart() async throws {
    let generator = RecordingGenerator { "\n\n  \($0) \n" }
    let steps = try await collect(rewriter(generator: generator), "A.\n\nB.", .fixGrammar)
    #expect(steps.last?.text == "A.\n\nB.")
}

@Test("a failure part-way through surfaces instead of returning a truncated rewrite")
func failurePropagates() async throws {
    let generator = RecordingGenerator(failAt: 2)
    await #expect(throws: StubError.self) {
        try await rewriter(generator: generator).run("A.\n\nB.\n\nC.", action: .fixGrammar) { _ in }
    }
    #expect(await generator.seen().count == 2)
}

@Test("cancelling stops before the next model call")
func cancellationStops() async throws {
    let generator = RecordingGenerator()
    let text = (1...20).map { "Paragraph \($0)." }.joined(separator: "\n\n")

    await #expect(throws: CancellationError.self) {
        try await collect(rewriter(generator: generator), text, .fixGrammar, stoppingAfter: 2)
    }
    // The two parts already asked for ran; the remaining eighteen never started.
    #expect(await generator.seen().count == 2)
}
