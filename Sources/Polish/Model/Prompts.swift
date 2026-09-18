import Foundation

/// Every instruction string the app sends to the model, in one place so they can be reviewed and
/// token-counted together. Each is imperative, output-only, and under 120 tokens — the budget in
/// `PRD.md` "Token budget per action"; `PromptsTests` enforces it.
///
/// Rules for editing: no examples (they cost tokens the input needs), no "you are a…" persona, and
/// every prompt ends by forbidding a preamble, because a 3B model volunteers one otherwise.
enum Prompts {
    static let fixGrammar = """
        Correct only the spelling, grammar and punctuation of the user's text. \
        Keep the wording, tone and length as they are. Do not rephrase, explain or add anything. \
        Return only the corrected text, with no preamble.
        """

    static let improve = """
        Rewrite the user's text so it reads clearly and naturally. \
        Keep the meaning and stay within 20% of the original length. \
        Do not add facts, opinions or detail that is not already there. \
        Return only the rewritten text, with no preamble.
        """

    static func summarize(_ style: SummaryStyle) -> String {
        switch style {
        case .bullets:
            """
            Summarize the user's text as three short bullet points, each starting with "- ". \
            Use only what the text states; add nothing. \
            Return only the bullets, with no preamble.
            """
        case .paragraph:
            """
            Summarize the user's text as one short paragraph of at most three sentences. \
            Use only what the text states; add nothing. \
            Return only the summary, with no preamble.
            """
        }
    }

    /// The map pass of a long summary: denser than the final answer, and told to treat the
    /// carried-forward context as context rather than material to summarize again.
    static let summarizeChunk = """
        Summarize the user's text in at most four short sentences. \
        Keep names, numbers, decisions and open questions; drop pleasantries. \
        Any text under "Earlier:" is a summary of what came before — use it for continuity, \
        do not repeat it. Return only the summary, with no preamble.
        """

    static let shorten = """
        Rewrite the user's text about 40% shorter. \
        Keep every fact, name, number and commitment; cut filler and repetition instead. \
        Return only the shortened text, with no preamble.
        """

    static let expand = """
        Turn the user's notes or bullet points into complete sentences. \
        Add only the connective words the notes imply — no new facts, opinions or detail. \
        Return only the prose, with no preamble.
        """

    static func changeTone(_ tone: Tone) -> String {
        """
        Rewrite the user's text so it sounds \(toneClause(tone)). \
        Keep the meaning, every fact, and roughly the original length. \
        Return only the rewritten text, with no preamble.
        """
    }

    /// `summaryStyle` defaults to the stored preference so callers that only have an `Action`
    /// (the popover, `TokenBudget`) need not thread it through.
    static func instructions(for action: Action, summaryStyle: SummaryStyle = Preferences.summaryStyle()) -> String {
        switch action {
        case .fixGrammar: fixGrammar
        case .improve: improve
        case .summarize: summarize(summaryStyle)
        case .shorten: shorten
        case .changeTone(let tone): changeTone(tone)
        case .expand: expand
        }
    }

    /// Every instruction the app can send, for the token-budget test.
    static var all: [String] {
        // De-duplicated: whichever summary style is stored also comes back through `Action.grid`.
        Array(Set(
            Action.grid.map { instructions(for: $0) }
                + Tone.allCases.map(changeTone)
                + SummaryStyle.allCases.map(summarize)
                + [summarizeChunk]
        ))
    }

    private static func toneClause(_ tone: Tone) -> String {
        switch tone {
        case .professional: "professional and polished, fit for a work email"
        case .friendly: "warm and friendly, as if writing to a colleague you like"
        case .direct: "direct and plain, with no hedging or filler"
        case .apologetic: "apologetic and considerate, acknowledging the inconvenience"
        }
    }
}
