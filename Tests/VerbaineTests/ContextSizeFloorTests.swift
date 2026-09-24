import Foundation
import Testing
@testable import Polish

/// M3: a declared context window too small for the chunkers used to produce an empty "result"
/// that `Replace` would paste over the user's selection. Two ends are covered here: the floor
/// Settings clamps to, and the chunkers refusing to hand back nothing.

/// One token per word, as in `ParagraphRewriterTests`.
private struct WordCounter: TokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

/// Answers with the prompt it was given, so an empty result can only come from the budget.
private struct EchoGenerator: TextGenerating {
    func respond(instructions: String, prompt: String) async throws -> String { prompt }
}

/// Counts every instruction at the worst case the prompt budget allows, which is what the floor
/// is derived against.
private struct WorstCaseInstructionCounter: TokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        Prompts.all.contains(text) ? Prompts.maxInstructionTokens : text.split(whereSeparator: \.isWhitespace).count
    }
}

private func rewriter(contextSize: Int, counter: any TokenCounting = WordCounter()) -> ParagraphRewriter {
    ParagraphRewriter(
        generator: EchoGenerator(),
        budget: TokenBudget(contextSize: contextSize, counter: counter),
        chunker: TextChunker(counter: counter)
    )
}

private func summarizer(contextSize: Int, counter: any TokenCounting = WordCounter()) -> MapReduceSummarizer {
    MapReduceSummarizer(
        generator: EchoGenerator(),
        budget: TokenBudget(contextSize: contextSize, counter: counter),
        chunker: TextChunker(counter: counter)
    )
}

// MARK: - The floor itself

@Test("the floor is the budget arithmetic, not a round number")
func floorIsDerivedFromTheBudget() {
    // The tightest path is a chunked summary: contextSize − instructions − wrapper − margin
    // − condensingOutputReserve − carry has to leave at least one token to chunk with.
    #expect(
        TokenBudget.minimumViableContextSize
            == Prompts.maxInstructionTokens + TokenBudget.wrapperTokens + TokenBudget.margin
                + TokenBudget.condensingOutputReserve + MapReduceSummarizer.carryTokens + 1
    )
    #expect(TokenBudget.minimumViableContextSize == 851)
}

@Test("at the floor, with the largest instruction the prompt budget allows, every path still has room")
func floorLeavesRoomForEveryPath() async throws {
    let counter = WorstCaseInstructionCounter()
    let budget = TokenBudget(contextSize: TokenBudget.minimumViableContextSize, counter: counter)

    let condensing = try await budget.maxSinglePassInputTokens(for: .summarize)
    // What `MapReduceSummarizer.chunkSize` computes: it has to stay positive.
    #expect(condensing - MapReduceSummarizer.carryTokens >= 1)
    #expect(try await budget.maxSinglePassInputTokens(for: .improve) > 0)
}

@Test("one token under the floor, the summarize chunk budget collapses to nothing")
func oneUnderTheFloorCollapses() async throws {
    let counter = WorstCaseInstructionCounter()
    let budget = TokenBudget(contextSize: TokenBudget.minimumViableContextSize - 1, counter: counter)
    let condensing = try await budget.maxSinglePassInputTokens(for: .summarize)
    #expect(condensing - MapReduceSummarizer.carryTokens <= 0)
}

// MARK: - Settings clamps the typed value

@Test("a context size typed as 128 — meaning 128k — is floored, not stored as 128")
func settingsFloorsAnUnusableContextSize() {
    let defaults = UserDefaults(suiteName: "polish.tests.\(UUID().uuidString)")!
    Preferences.setRemoteConfig(
        RemoteConfig(baseURL: "https://api.example.com/v1", model: "m", contextSize: 128),
        defaults
    )
    #expect(Preferences.remoteConfig(defaults).contextSize == TokenBudget.minimumViableContextSize)
}

@Test("zero and negative context sizes are floored too")
func settingsFloorsNonPositiveContextSizes() {
    for typed in [0, -1, 1] {
        let defaults = UserDefaults(suiteName: "polish.tests.\(UUID().uuidString)")!
        Preferences.setRemoteConfig(
            RemoteConfig(baseURL: "https://api.example.com/v1", model: "m", contextSize: typed),
            defaults
        )
        #expect(Preferences.remoteConfig(defaults).contextSize == TokenBudget.minimumViableContextSize)
    }
}

@Test("a real window is stored exactly as typed")
func settingsKeepsAUsableContextSize() {
    let defaults = UserDefaults(suiteName: "polish.tests.\(UUID().uuidString)")!
    Preferences.setRemoteConfig(
        RemoteConfig(baseURL: "https://api.example.com/v1", model: "m", contextSize: 128_000),
        defaults
    )
    #expect(Preferences.remoteConfig(defaults).contextSize == 128_000)
}

@Test("a sub-floor value already sitting in defaults is floored on the way out")
func alreadyStoredSubFloorValueIsFloored() {
    let defaults = UserDefaults(suiteName: "polish.tests.\(UUID().uuidString)")!
    defaults.set(128, forKey: Preferences.remoteContextSizeKey)
    #expect(Preferences.remoteConfig(defaults).contextSize == TokenBudget.minimumViableContextSize)
}

// MARK: - The empty generation is an error, never a result

@Test("a rewrite with no room to work throws instead of returning an empty result")
func emptyRewriteThrows() async throws {
    // 130 = instructions (100 words) + wrapper + margin already over the window: no parts.
    #expect(try await rewriter(contextSize: 130).parts(of: "Some selected text.", action: .improve).isEmpty)

    await #expect(throws: UserFacingError.emptyResult) {
        _ = try await rewriter(contextSize: 130).run("Some selected text.", action: .improve) { _ in }
    }
}

@Test("a summary with no room to work throws instead of returning an empty result")
func emptySummaryThrows() async throws {
    #expect(try await summarizer(contextSize: 400).parts(of: "Some selected text.").isEmpty)

    await #expect(throws: UserFacingError.emptyResult) {
        _ = try await summarizer(contextSize: 400).run("Some selected text.") { _ in }
    }
}

@Test("a generator that answers with nothing but whitespace is a failure, not an empty rewrite")
func whitespaceOnlyAnswerThrows() async throws {
    struct BlankGenerator: TextGenerating {
        func respond(instructions: String, prompt: String) async throws -> String { "   \n " }
    }
    let counter = WordCounter()
    let rewriter = ParagraphRewriter(
        generator: BlankGenerator(),
        budget: TokenBudget(contextSize: 4_096, counter: counter),
        chunker: TextChunker(counter: counter)
    )

    await #expect(throws: UserFacingError.emptyResult) {
        _ = try await rewriter.run("Some selected text.", action: .improve) { _ in }
    }
}

@Test("the empty-result error offers the input back rather than a retry that would repeat it")
func emptyResultOffersTheOriginal() {
    #expect(UserFacingError.emptyResult.remedy == .copyOriginal)
    #expect(UserFacingError(UserFacingError.emptyResult) == UserFacingError.emptyResult)
}

@Test("a rewrite that does have room still returns its text")
func usableWindowStillProducesAResult() async throws {
    let result = try await rewriter(contextSize: 4_096).run("Some selected text.", action: .improve) { _ in }
    #expect(result == "Some selected text.")
}
