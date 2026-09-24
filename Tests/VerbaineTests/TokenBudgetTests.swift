import Testing
@testable import Verbaine

/// Counts a fixed number of tokens per call so the arithmetic under test is the only variable.
private struct StubCounter: TokenCounting {
    var instructionTokens = 100
    var perText: [String: Int] = [:]

    func tokenCount(for text: String) async throws -> Int {
        if let count = perText[text] { return count }
        // Anything that is not a known input is an instruction string.
        return instructionTokens
    }
}

private func budget(context: Int = 4096, instructions: Int = 100, texts: [String: Int] = [:]) -> TokenBudget {
    TokenBudget(contextSize: context, counter: StubCounter(instructionTokens: instructions, perText: texts))
}

@Test("a rewrite reserves 1.3× the input for the answer")
func rewriteBudget() async throws {
    // 4096 − (100 + 30 + 150) = 3,816 available, split over input + 1.3 × input.
    let max = try await budget().maxSinglePassInputTokens(for: .fixGrammar)
    #expect(max == 1659)
}

@Test("summarize and shorten reserve a flat 400 tokens", arguments: [Action.summarize, .shorten])
func condensingBudget(action: Action) async throws {
    let max = try await budget().maxSinglePassInputTokens(for: action)
    #expect(max == 4096 - 100 - 30 - 150 - 400)
}

@Test("every tone is budgeted as a rewrite", arguments: Tone.allCases)
func tonesAreRewrites(tone: Tone) async throws {
    let rewrite = try await budget().maxSinglePassInputTokens(for: .changeTone(tone))
    let condensing = try await budget().maxSinglePassInputTokens(for: .summarize)
    #expect(rewrite != condensing)
    #expect(rewrite == 1659)
}

@Test("a bigger context window raises the budget without any code change")
func budgetScalesWithContextSize() async throws {
    let small = try await budget(context: 4096).maxSinglePassInputTokens(for: .improve)
    let large = try await budget(context: 16_384).maxSinglePassInputTokens(for: .improve)
    #expect(large > small * 3)
}

@Test("instructions that swallow the window leave a zero budget, never a negative one")
func neverNegative() async throws {
    let max = try await budget(context: 200, instructions: 180).maxSinglePassInputTokens(for: .summarize)
    #expect(max == 0)
}

@Test("input at the limit fits and one token more does not")
func fitsAtTheBoundary() async throws {
    let subject = budget(texts: ["at limit": 1659, "over limit": 1660])
    let atLimit = try await subject.fitsInOnePass(action: .fixGrammar, text: "at limit")
    let overLimit = try await subject.fitsInOnePass(action: .fixGrammar, text: "over limit")
    #expect(atLimit)
    #expect(!overLimit)
}

@Test("a short message fits every action", arguments: Action.grid)
func shortTextAlwaysFits(action: Action) async throws {
    let subject = budget(texts: ["hi": 1])
    let fits = try await subject.fitsInOnePass(action: action, text: "hi")
    #expect(fits)
}
