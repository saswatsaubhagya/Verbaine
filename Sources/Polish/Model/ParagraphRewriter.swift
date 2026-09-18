import Foundation

/// Runs a rewrite that does not fit one model call, one paragraph at a time.
///
/// `PRD.md` "Chunking rules": rewrites go paragraph-by-paragraph, sequentially, each in its own
/// fresh session, and the pieces are stitched back in order with the blank lines between them.
/// Sequential is deliberate — the model is a single on-device resource, and parallel calls would
/// queue behind each other anyway while making progress reporting a lie.
struct ParagraphRewriter: Sendable {
    /// Cumulative state after each paragraph: the stitched text so far, and where we are.
    typealias Progress = PartProgress

    private let generator: any TextGenerating
    private let budget: TokenBudget
    private let chunker: TextChunker

    init(generator: any TextGenerating, budget: TokenBudget, chunker: TextChunker) {
        self.generator = generator
        self.budget = budget
        self.chunker = chunker
    }

    init(service: any InferenceProvider = Inference.current) {
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
            let rewritten = try await ContextRetry.run(part) {
                try await generator.respond(instructions: action.instructions, prompt: $0)
            }
            done.append(rewritten.trimmingCharacters(in: .whitespacesAndNewlines))
            await onPart(Progress(part: index + 1, total: parts.count, text: done.joined(separator: "\n\n")))
        }
        let result = done.joined(separator: "\n\n")
        // No parts (a window too small to carve one out of) or nothing but whitespace back: an
        // empty rewrite must not reach the popover as a result the user can press Replace on.
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UserFacingError.emptyResult
        }
        return result
    }
}
