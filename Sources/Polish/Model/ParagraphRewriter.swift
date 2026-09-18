import Foundation

/// Anything that can answer one prompt. `ModelService` is the real one; tests stub it so they run
/// on machines without Apple Intelligence.
protocol TextGenerating: Sendable {
    func respond(instructions: String, prompt: String) async throws -> String
}

extension ModelService: TextGenerating {}

/// Runs a rewrite that does not fit one model call, one paragraph at a time.
///
/// `PRD.md` "Chunking rules": rewrites go paragraph-by-paragraph, sequentially, each in its own
/// fresh session, and the pieces are stitched back in order with the blank lines between them.
/// Sequential is deliberate — the model is a single on-device resource, and parallel calls would
/// queue behind each other anyway while making progress reporting a lie.
struct ParagraphRewriter: Sendable {
    /// Cumulative state after each paragraph: the stitched text so far, and where we are.
    struct Progress: Sendable, Equatable {
        let part: Int
        let total: Int
        let text: String
    }

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

    /// The paragraphs this rewrite will run as, in order. A paragraph too large for one call is
    /// split further on sentence boundaries, so every part is guaranteed to fit.
    func parts(of text: String, action: Action) async throws -> [String] {
        let limit = try await budget.maxSinglePassInputTokens(for: action)
        guard limit > 0 else { return [] }

        var parts: [String] = []
        for paragraph in TextChunker.paragraphs(text) {
            if try await chunker.counter.tokenCount(for: paragraph) <= limit {
                parts.append(paragraph)
            } else {
                // No overlap: a rewrite must not emit the same sentence twice.
                parts += try await chunker.budgeted(paragraph, maxTokens: limit, overlapSentences: 0)
            }
        }
        return parts
    }

    /// Rewrites `text` part by part, calling `onPart` with the stitched result after each one.
    ///
    /// Runs inline on the caller's task — no detached producer — so cancelling the caller stops
    /// before the next model call and the part in flight is never half-written into the result.
    @discardableResult
    func run(
        _ text: String,
        action: Action,
        onPart: @Sendable (Progress) async -> Void
    ) async throws -> String {
        let parts = try await parts(of: text, action: action)
        var done: [String] = []
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            let rewritten = try await generator.respond(instructions: action.instructions, prompt: part)
            done.append(rewritten.trimmingCharacters(in: .whitespacesAndNewlines))
            await onPart(Progress(part: index + 1, total: parts.count, text: done.joined(separator: "\n\n")))
        }
        return done.joined(separator: "\n\n")
    }
}
