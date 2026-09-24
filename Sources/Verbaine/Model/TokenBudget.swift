import Foundation

/// Decides whether an action's input fits a single model call.
///
/// Everything shares one window: instructions, the prompt wrapper, the input, and the model's own
/// output. The budget below is `PRD.md` "Token budget per action (single pass)"; `contextSize` is
/// read from the model, never assumed.
struct TokenBudget: Sendable {
    /// "Improve this text:" and friends, measured once in the PRD at ≤ 30 tokens.
    static let wrapperTokens = 30
    /// Slack for tokenizer disagreement between our count and the model's.
    static let margin = 150
    /// Summaries and shortenings return far less than they take in.
    static let condensingOutputReserve = 400
    /// A rewrite can come back longer than the input — expansion, politeness padding, tone changes.
    static let rewriteOutputRatio = 1.3

    /// The smallest declared context window in which every path still has room to do its work.
    ///
    /// Derived from the arithmetic above rather than picked: the tightest path is a chunked
    /// summary, whose per-chunk budget is
    /// `contextSize − instructions − wrapper − margin − condensingOutputReserve − carry`, and
    /// that has to come out at one token or more. With the worst-case instruction
    /// (`Prompts.maxInstructionTokens`, the ceiling `PromptsTests` enforces) that is
    /// `120 + 30 + 150 + 400 + 150 + 1 = 851`.
    ///
    /// Below this, `ParagraphRewriter.parts` and `MapReduceSummarizer.parts` return no parts at
    /// all and the run produces the empty string — which, before this floor, was committed as a
    /// result and could be pasted over the user's selection. Reachable only because the remote
    /// provider's window is typed by hand in Settings: entering `128` meaning 128k gives a
    /// per-chunk budget of zero.
    static let minimumViableContextSize =
        Prompts.maxInstructionTokens + wrapperTokens + margin
            + condensingOutputReserve + MapReduceSummarizer.carryTokens + 1

    let contextSize: Int
    private let counter: any TokenCounting

    init(contextSize: Int, counter: any TokenCounting) {
        self.contextSize = contextSize
        self.counter = counter
    }

    init(service: any InferenceProvider = Inference.current) {
        self.init(contextSize: service.contextSize, counter: service)
    }

    /// The largest input, in tokens, that still leaves room for the instructions and the answer.
    ///
    /// Returns 0 when the instructions alone leave no room, so callers never see a negative budget.
    func maxSinglePassInputTokens(for action: Action) async throws -> Int {
        let instructionTokens = try await counter.tokenCount(for: action.instructions)
        let fixedCost = instructionTokens + Self.wrapperTokens + Self.margin

        if action.isRewrite {
            // input + input × 1.3 + fixedCost ≤ contextSize
            let available = Double(contextSize - fixedCost)
            return max(0, Int((available / (1 + Self.rewriteOutputRatio)).rounded(.down)))
        } else {
            return max(0, contextSize - fixedCost - Self.condensingOutputReserve)
        }
    }

    func fitsInOnePass(action: Action, text: String) async throws -> Bool {
        let inputTokens = try await counter.tokenCount(for: text)
        let limit = try await maxSinglePassInputTokens(for: action)
        return inputTokens <= limit
    }
}
