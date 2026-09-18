import Foundation

/// What the popover tells the user about the selection *before* anything runs: how big it is, how
/// many parts it will take, and — past 12,000 tokens — which actions are still worth offering.
///
/// `PRD.md` "Strategy by text length" is the source of truth. The part count here is the rewrite
/// path (one part per paragraph); a summary chunks differently, and the running view replaces this
/// with the real "Part 3 of 8" from `PartProgress` as soon as generation starts.
// ponytail: one estimate for both paths instead of one per action — the label is a heads-up, not a contract.
struct SizeEstimate: Sendable, Equatable {
    /// Past this, Improve/Shorten/Tone/Expand are slow enough to be a bad deal (PRD row 3).
    static let veryLongTokens = 12_000

    let tokens: Int
    /// 1 when the whole selection fits one model call.
    let parts: Int

    var isLong: Bool { parts > 1 }
    var isVeryLong: Bool { tokens > Self.veryLongTokens }

    /// Over 12,000 tokens only the two actions that stay useful at that length are offered.
    func isEnabled(_ action: Action) -> Bool {
        guard isVeryLong else { return true }
        return action == .fixGrammar || action == .summarize
    }

    /// Whether a per-action shortcut (T3.2) may run this action and replace without showing the
    /// popover. A multi-part run takes long enough that the user should see progress and be able
    /// to cancel it, and an action this selection is too long for must not run at all.
    func allowsSilentRun(_ action: Action) -> Bool { !isLong && isEnabled(action) }

    var label: String {
        let count = "~\(tokens.formatted()) tokens"
        return isLong ? "\(count) · Long text — processing in \(parts) parts" : count
    }

    var warning: String? {
        isVeryLong ? "Very long selection. Only Fix grammar and Summarize are offered; both run in parts and can be cancelled." : nil
    }

    /// - Parameters:
    ///   - paragraphs: paragraph count from `TextChunker.paragraphs`, i.e. the rewrite part count.
    ///   - singlePassLimit: `TokenBudget.maxSinglePassInputTokens(for:)`.
    static func make(tokens: Int, paragraphs: Int, singlePassLimit: Int) -> SizeEstimate {
        SizeEstimate(tokens: tokens, parts: tokens <= singlePassLimit ? 1 : max(2, paragraphs))
    }
}
