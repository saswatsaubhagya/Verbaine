import Foundation
import Testing
@testable import Polish

/// One token per word, as in `TextChunkerTests`, so the packing arithmetic is the only variable.
private struct WordCounter: TokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Records every call and answers with a short, deterministic "summary" so the map and reduce
/// passes can be told apart by their instructions.
private actor RecordingGenerator: TextGenerating {
    struct Call: Sendable {
        let instructions: String
        let prompt: String

        var isMap: Bool { instructions == Prompts.summarizeChunk }
    }

    private(set) var calls: [Call] = []
    private let transform: @Sendable (Call) -> String

    init(transform: @escaping @Sendable (Call) -> String = { "S\($0.prompt.prefix(8))" }) {
        self.transform = transform
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        let call = Call(instructions: instructions, prompt: prompt)
        calls.append(call)
        return transform(call)
    }

    func seen() -> [Call] { calls }
}

private func summarizer(
    generator: any TextGenerating,
    contextSize: Int = 4096
) -> MapReduceSummarizer {
    let counter = WordCounter()
    return MapReduceSummarizer(
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

/// The fixture repeated until it is at least `words` long — the 5,000-word thread from T2.3.
private func longThread(words: Int = 5_000) throws -> String {
    let base = try fixture("chat-thread.txt")
    let count = base.split(whereSeparator: \.isWhitespace).count
    return Array(repeating: base, count: max(1, Int(ceil(Double(words) / Double(count)))))
        .joined(separator: "\n")
}

private actor Steps {
    private var steps: [PartProgress] = []
    func append(_ step: PartProgress) { steps.append(step) }
    func count() -> Int { steps.count }
    func all() -> [PartProgress] { steps }
}

private func collect(
    _ summarizer: MapReduceSummarizer,
    _ text: String,
    stoppingAfter limit: Int? = nil
) async throws -> [PartProgress] {
    let box = Steps()
    try await summarizer.run(text) { step in
        await box.append(step)
        if let limit, await box.count() >= limit { withUnsafeCurrentTask { $0?.cancel() } }
    }
    return await box.all()
}

// MARK: - Chunking

@Test("chunks stay within the measured budget, never the hard-coded 2,500")
func chunksFitTheBudget() async throws {
    let text = try longThread()
    let limit = try await TokenBudget(contextSize: 1_200, counter: WordCounter())
        .maxSinglePassInputTokens(for: .summarize)
    let parts = try await summarizer(generator: RecordingGenerator(), contextSize: 1_200).parts(of: text)

    #expect(parts.count > 1)
    for part in parts {
        #expect(part.split(whereSeparator: \.isWhitespace).count <= limit - MapReduceSummarizer.carryTokens)
    }
}

@Test("chunks overlap by a sentence so the thread survives the split")
func chunksOverlap() async throws {
    let text = (1...200).map { "Message number \($0) said something." }.joined(separator: " ")
    let parts = try await summarizer(generator: RecordingGenerator(), contextSize: 1_000).parts(of: text)

    #expect(parts.count > 1)
    for (previous, next) in zip(parts, parts.dropFirst()) {
        let tail = TextChunker.sentences(previous).last
        #expect(TextChunker.sentences(next).first == tail)
    }
}

@Test("instructions that leave no room produce no parts rather than a negative budget")
func summaryNoBudgetNoParts() async throws {
    let parts = try await summarizer(generator: RecordingGenerator(), contextSize: 200).parts(of: "Anything at all.")
    #expect(parts.isEmpty)
}

// MARK: - Map pass

@Test("every chunk after the first carries the previous chunk's summary")
func carriesPreviousSummaryForward() async throws {
    let generator = RecordingGenerator { _ in "The previous part said this." }
    _ = try await collect(summarizer(generator: generator, contextSize: 1_000), try longThread(words: 2_000))
    let map = await generator.seen().filter(\.isMap)

    #expect(map.count > 1)
    #expect(!map[0].prompt.hasPrefix("Earlier:"))
    for call in map.dropFirst() {
        #expect(call.prompt.hasPrefix("Earlier:\nThe previous part said this.\n\nText:\n"))
    }
}

@Test("a carried summary is capped at 150 tokens, on a sentence boundary")
func carryIsCapped() async throws {
    // Twenty sentences of ten words: 200 tokens, over the 150-token cap.
    let verbose = (1...20).map { "Sentence \($0) has exactly ten words in it here." }
        .joined(separator: " ")
    let generator = RecordingGenerator { _ in verbose }
    _ = try await collect(summarizer(generator: generator, contextSize: 1_000), try longThread(words: 2_000))

    let carried = await generator.seen()
        .filter { $0.isMap && $0.prompt.hasPrefix("Earlier:") }
        .map { String($0.prompt.dropFirst("Earlier:\n".count).prefix(while: { $0 != "\n" })) }

    #expect(!carried.isEmpty)
    for carry in carried {
        #expect(carry.split(whereSeparator: \.isWhitespace).count <= MapReduceSummarizer.carryTokens)
        #expect(carry.hasSuffix("."))
    }
}

// MARK: - Reduce pass

@Test("a 5,000-word thread summarizes with one reduce call in the user's style")
func fiveThousandWordsReduceOnce() async throws {
    let generator = RecordingGenerator()
    let result = try await summarizer(generator: generator, contextSize: 4_096)
        .run(try longThread(), action: .summarize) { _ in }
    let calls = await generator.seen()

    let mapOnlyPrefix = calls.dropLast().allSatisfy { $0.isMap }
    #expect(mapOnlyPrefix)
    #expect(calls.last?.instructions == Action.summarize.instructions)
    #expect(!result.isEmpty)
    // The reduce prompt is the map summaries, not the original thread.
    let reducePrompt = try #require(calls.last).prompt
    let fits = try await TokenBudget(contextSize: 4_096, counter: WordCounter())
        .fitsInOnePass(action: .summarize, text: reducePrompt)
    #expect(fits)
}

@Test("summaries too large for one reduce run a second reduce level")
func secondReduceLevel() async throws {
    // Each map summary is 80 words; a narrow window cannot hold them all at once.
    let generator = RecordingGenerator { call in
        call.isMap ? (1...8).map { _ in "ten words here to pad the summary out now." }.joined(separator: " ")
                   : "- one\n- two\n- three"
    }
    let summarizer = summarizer(generator: generator, contextSize: 1_000)
    let result = try await summarizer.run(try longThread(), action: .summarize) { _ in }
    let calls = await generator.seen()
    let chunks = try await summarizer.parts(of: try longThread())

    // More map-instruction calls than there are chunks: the extras are the second reduce level.
    #expect(calls.filter(\.isMap).count > chunks.count)
    #expect(calls.filter { !$0.isMap }.count == 1)
    #expect(result == "- one\n- two\n- three")
}

// MARK: - Progress and cancellation

@Test("progress runs 1...n for the chunks and ends on the reduce, carrying the final answer")
func progressEndsOnTheReduce() async throws {
    let generator = RecordingGenerator { $0.isMap ? "chunk summary." : "final answer." }
    let text = try longThread(words: 2_000)
    let summarizer = summarizer(generator: generator, contextSize: 1_000)
    let chunks = try await summarizer.parts(of: text)
    let steps = try await collect(summarizer, text)

    #expect(steps.map(\.part) == Array(1...(chunks.count + 1)))
    #expect(steps.allSatisfy { $0.total == chunks.count + 1 })
    #expect(steps.last?.text == "final answer.")
}

@Test("cancelling stops before the next model call")
func summaryCancellationStops() async throws {
    let generator = RecordingGenerator()
    await #expect(throws: CancellationError.self) {
        try await collect(summarizer(generator: generator, contextSize: 1_000), try longThread(), stoppingAfter: 2)
    }
    #expect(await generator.seen().count == 2)
}

@Test("empty input asks the model nothing, and is a failure rather than an empty summary")
func emptyInput() async throws {
    // Capture refuses an empty selection long before this, so reaching here at all is a bug;
    // M3 is that it must not read as a finished, empty result the user can press Replace on.
    let generator = RecordingGenerator()
    await #expect(throws: UserFacingError.emptyResult) {
        _ = try await summarizer(generator: generator).run("   \n  ", action: .summarize) { _ in }
    }
    #expect(await generator.seen().isEmpty)
}
