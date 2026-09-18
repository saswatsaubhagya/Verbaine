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

    static let summarize = """
        Summarize the user's text as three short bullet points, each starting with "- ". \
        Use only what the text states; add nothing. \
        Return only the bullets, with no preamble.
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

    static func instructions(for action: Action) -> String {
        switch action {
        case .fixGrammar: fixGrammar
        case .improve: improve
        case .summarize: summarize
        case .shorten: shorten
        case .changeTone(let tone): changeTone(tone)
        case .expand: expand
        }
    }

    /// Every instruction the app can send, for the token-budget test.
    static var all: [String] {
        Action.grid.map(instructions(for:)) + Tone.allCases.map(changeTone)
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
