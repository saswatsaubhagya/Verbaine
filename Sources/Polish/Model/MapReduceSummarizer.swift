import Foundation

/// Summarizes text that does not fit one model call, by map-reduce.
///
/// `PRD.md` "Chunking rules": chunks of ~2,500 tokens with a one-sentence overlap, each prompt
/// carrying the previous chunk's summary (capped at 150 tokens) so the thread survives the split;
/// then one final session summarizes the summaries. If the summaries themselves do not fit, they
/// are summarized in groups first — a second reduce level, repeated until one call is enough.
///
/// Sequential for the same reason as ``ParagraphRewriter``: one model, and each chunk's prompt
/// depends on the previous chunk's answer.
struct MapReduceSummarizer: Sendable {
    typealias Progress = PartProgress

    /// `PRD.md` "Chunking rules". The real chunk size is the smaller of this and what the window
    /// allows, so a narrower context window shrinks it rather than overflowing.
    static let targetChunkTokens = 2_500
    /// How much of the previous chunk's summary rides along with the next chunk.
    static let carryTokens = 150

    private let generator: any TextGenerating
    private let budget: TokenBudget
    private let chunker: TextChunker

    init(generator: any TextGenerating, budget: TokenBudget, chunker: TextChunker) {
        self.generator = generator
        self.budget = budget
        self.chunker = chunker
    }

    init(service: ModelService = .shared) {
        self.init(generator: service, budget: TokenBudget(service: service), chunker: TextChunker(service: service))
    }

    /// The chunks the map pass will run as, in order.
    func parts(of text: String) async throws -> [String] {
        let size = try await chunkSize()
        guard size > 0 else { return [] }
        return try await chunker.budgeted(text, maxTokens: size, overlapSentences: 1)
    }

    /// Summarizes `text`, calling `onPart` after each chunk and once more after the final reduce.
    ///
    /// Runs inline on the caller's task, so cancelling stops before the next model call.
    @discardableResult
    func run(
        _ text: String,
        action: Action = .summarize,
        onPart: @Sendable (Progress) async -> Void
    ) async throws -> String {
        let chunks = try await parts(of: text)
        guard !chunks.isEmpty else { return "" }
        let total = chunks.count + 1  // the map pass, plus the final reduce.

        // Map: one summary per chunk, each told what came before.
        var summaries: [String] = []
        var carry = ""
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let summary = try await generator.respond(
                instructions: Prompts.summarizeChunk,
                prompt: carry.isEmpty ? chunk : "Earlier:\n\(carry)\n\nText:\n\(chunk)"
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            summaries.append(summary)
            carry = try await capped(summary, to: Self.carryTokens)
            await onPart(Progress(part: index + 1, total: total, text: summaries.joined(separator: "\n\n")))
        }

        // Reduce: collapse the summaries until they fit one call, then summarize them in the
        // user's chosen style.
        var combined = summaries.joined(separator: "\n\n")
        while summaries.count > 1,
              try await !budget.fitsInOnePass(action: action, text: combined) {
            summaries = try await reduceOnce(summaries)
            combined = summaries.joined(separator: "\n\n")
        }

        try Task.checkCancellation()
        let result = try await generator.respond(instructions: action.instructions, prompt: combined)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        await onPart(Progress(part: total, total: total, text: result))
        return result
    }

    /// One extra reduce level: summaries packed into groups, each group summarized into one.
    ///
    /// Every group takes at least two summaries, so the count strictly shrinks and the loop above
    /// always terminates.
    private func reduceOnce(_ summaries: [String]) async throws -> [String] {
        let size = try await chunkSize()
        var groups: [[String]] = []
        var current: [String] = []
        var cost = 0

        for summary in summaries {
            let tokens = try await chunker.counter.tokenCount(for: summary)
            if current.count >= 2, cost + tokens > size {
                groups.append(current)
                current = []
                cost = 0
            }
            current.append(summary)
            cost += tokens
        }
        if !current.isEmpty { groups.append(current) }

        var reduced: [String] = []
        for group in groups {
            try Task.checkCancellation()
            // ponytail: a pair of summaries over budget would still be sent; the T2.5
            // contextSizeExceeded retry is the backstop, and four-sentence summaries make it moot.
            reduced.append(
                try await generator.respond(
                    instructions: Prompts.summarizeChunk,
                    prompt: group.joined(separator: "\n\n")
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return reduced
    }

    /// The chunk budget: the target size, or whatever the window leaves after the instructions,
    /// the carried summary and the output reserve — whichever is smaller.
    private func chunkSize() async throws -> Int {
        let limit = try await budget.maxSinglePassInputTokens(for: .summarize)
        return min(Self.targetChunkTokens, limit - Self.carryTokens)
    }

    /// Trims a summary to `maxTokens` on sentence boundaries, so the carried context never eats
    /// the next chunk's room.
    private func capped(_ summary: String, to maxTokens: Int) async throws -> String {
        guard try await chunker.counter.tokenCount(for: summary) > maxTokens else { return summary }

        var kept: [String] = []
        var cost = 0
        for sentence in TextChunker.sentences(summary) {
            let tokens = try await chunker.counter.tokenCount(for: sentence)
            if cost + tokens > maxTokens { break }
            kept.append(sentence)
            cost += tokens
        }
        return kept.joined(separator: " ")
    }
}
