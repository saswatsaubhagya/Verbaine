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
    /// A user-written action from Settings → Actions (T3.1).
    case custom(CustomAction)

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
        case .custom(let action): "custom.\(action.id.uuidString)"
        }
    }

    /// Rebuilds a built-in action from the `id` a shortcut was stored under. Custom actions are
    /// not reachable this way — they are looked up in `Preferences.customActions()` by UUID.
    init?(id: String) {
        guard let match = (Self.grid + Tone.allCases.map(Action.changeTone)).first(where: { $0.id == id })
        else { return nil }
        self = match
    }

    var title: String {
        switch self {
        case .fixGrammar: "Fix grammar"
        case .improve: "Improve"
        case .summarize: "Summarize"
        case .shorten: "Shorten"
        case .changeTone: "Change tone"
        case .expand: "Expand"
        case .custom(let action): action.name
        }
    }

    /// The tile glyph in the popover's action grid (design board row 8, "Action tile").
    var symbol: String {
        switch self {
        case .fixGrammar: "checkmark.circle"
        case .improve: "wand.and.sparkles"
        case .summarize: "list.bullet"
        case .shorten: "arrow.down.right.and.arrow.up.left"
        case .changeTone: "slider.horizontal.3"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .custom: "star"
        }
    }

    /// Rewrites return text the same size as the input; the other two shrink it. `TokenBudget`
    /// (T1.3) sizes the output reserve from this.
    var isRewrite: Bool {
        switch self {
        // A custom action counts as a rewrite: its output reserve is the larger of the two, and
        // there is no way to know from the user's wording which way it goes.
        case .fixGrammar, .improve, .changeTone, .expand, .custom: true
        case .summarize, .shorten: false
        }
    }

    var instructions: String { Prompts.instructions(for: self) }

    /// The button the result pane makes the default. Built-ins replace; a custom action decides.
    var defaultButton: CustomAction.DefaultButton {
        if case .custom(let action) = self { return action.defaultButton }
        return .replace
    }

    /// The grid, followed by the user's own actions.
    static func grid(customActions: [CustomAction] = Preferences.customActions()) -> [Action] {
        grid + customActions.map(Action.custom)
    }
}
