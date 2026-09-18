import Foundation

/// The tone `Action.changeTone` rewrites into. Raw values are stable — they go into `UserDefaults`
/// for the per-app presets in T3.3.
enum Tone: String, CaseIterable, Sendable, Identifiable {
    case professional, friendly, direct, apologetic

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

/// One transformation the user can run on a selection. `PRD.md` "MVP actions (v1)" is the source
/// of truth for what each one does; the wording lives in `Prompts.swift`.
enum Action: Hashable, Sendable, Identifiable {
    case fixGrammar
    case improve
    case summarize
    case shorten
    case changeTone(Tone)
    case expand

    /// The popover grid, in order. Change tone appears once and opens a sub-menu over `Tone.allCases`.
    static let grid: [Action] = [.fixGrammar, .improve, .summarize, .shorten, .changeTone(.professional), .expand]

    var id: String {
        switch self {
        case .fixGrammar: "fixGrammar"
        case .improve: "improve"
        case .summarize: "summarize"
        case .shorten: "shorten"
        case .changeTone(let tone): "changeTone.\(tone.rawValue)"
        case .expand: "expand"
        }
    }

    var title: String {
        switch self {
        case .fixGrammar: "Fix grammar"
        case .improve: "Improve"
        case .summarize: "Summarize"
        case .shorten: "Shorten"
        case .changeTone: "Change tone"
        case .expand: "Expand"
        }
    }

    /// Rewrites return text the same size as the input; the other two shrink it. `TokenBudget`
    /// (T1.3) sizes the output reserve from this.
    var isRewrite: Bool {
        switch self {
        case .fixGrammar, .improve, .changeTone, .expand: true
        case .summarize, .shorten: false
        }
    }

    var instructions: String { Prompts.instructions(for: self) }
}
