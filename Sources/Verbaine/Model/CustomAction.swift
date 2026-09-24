import Foundation

/// A user-written action: a name, the instruction it sends, and how it behaves once it has run.
///
/// Stored as JSON in `UserDefaults` (`Preferences.customActions`). `id` is what the popover grid
/// and the hotkey registration key on, so it survives renames.
struct CustomAction: Codable, Hashable, Sendable, Identifiable {
    /// Which button the result pane makes the default (⏎).
    enum DefaultButton: String, Codable, CaseIterable, Sendable, Identifiable {
        case replace, copy

        var id: String { rawValue }

        var title: String { rawValue.capitalized }
    }

    var id = UUID()
    var name: String
    var instruction: String
    var defaultButton: DefaultButton = .replace
    /// Runs this action straight from the keyboard; `nil` means grid-only.
    var hotkey: Hotkey?

    /// The PRD's per-action prompt budget is 120 tokens, but a user writing their own instruction
    /// gets more room — the input still has to fit around it, which `TokenBudget` enforces later.
    static let maxInstructionTokens = 300

    /// Why this action cannot be saved, or `nil` when it can. `tokens` is the measured instruction
    /// length; pure so it can be tested without Apple Intelligence.
    static func validationError(name: String, instruction: String, tokens: Int) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the action a name." }
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Write what the action should do." }
        if tokens > maxInstructionTokens {
            return "That instruction is \(tokens) tokens; the limit is \(maxInstructionTokens)."
        }
        return nil
    }

    /// Measures with the real tokenizer when the model is there. Without Apple Intelligence it
    /// falls back to 4 characters per token — the same upper bound `PromptsTests` uses — so the
    /// Settings field still validates on a machine that cannot run the model.
    static func tokenCount(of text: String) async -> Int {
        guard Inference.current.availability == .ready,
              let tokens = try? await Inference.current.tokenCount(for: text)
        else { return (text.count + 3) / 4 }
        return tokens
    }
}
