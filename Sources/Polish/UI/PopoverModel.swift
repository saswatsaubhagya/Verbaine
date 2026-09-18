import AppKit
import Observation
import os

/// State behind the action popover: which step it is on, what the model has streamed so far, and
/// the three things the user can do with the result.
@MainActor
@Observable
final class PopoverModel {
    enum Phase {
        case actions
        case running
        case result
        case failed(UserFacingError)
    }

    private static let log = Logger(subsystem: "com.saswat.polish", category: "Popover")

    let selection: Selection
    private(set) var phase: Phase = .actions
    private(set) var output = ""
    private(set) var action: Action?
    /// "Part 3 of 8" while a long rewrite runs, `nil` for a single-pass action.
    private(set) var progress: ParagraphRewriter.Progress?
    /// Dismisses the popover: Esc, Copy, or a failure the user closes.
    var onClose: () -> Void = {}
    /// Dismisses the popover and hands over to the undo toast (T1.5).
    var onReplaced: () -> Void = {}

    private var generation: Task<Void, Never>?

    init(selection: Selection) {
        self.selection = selection
    }

    var diff: [DiffEngine.Segment] {
        DiffEngine.diff(original: selection.text, result: output)
    }

    func run(_ action: Action) {
        self.action = action
        generation?.cancel()
        output = ""

        // Asking an unavailable model produces a framework error a sentence later; the
        // availability check says the useful thing (turn Apple Intelligence on) instead.
        if let unavailable = UserFacingError(ModelService.shared.availability) {
            phase = .failed(unavailable)
            return
        }
        phase = .running
        progress = nil

        generation = Task { [selection] in
            do {
                // Non-rewrites over budget still go single-pass until T2.3 lands map-reduce.
                if try await TokenBudget().fitsInOnePass(action: action, text: selection.text)
                    || !action.isRewrite {
                    try await streamSinglePass(action, text: selection.text)
                } else {
                    try await streamByParagraph(action, text: selection.text)
                }
                guard !Task.isCancelled else { return }
                phase = .result
            } catch is CancellationError {
                return
            } catch {
                Self.log.error("generation failed: \(String(describing: error))")
                phase = .failed(UserFacingError(error))
            }
        }
    }

    /// Short input: one call, streamed token by token.
    private func streamSinglePass(_ action: Action, text: String) async throws {
        for try await snapshot in await ModelService.shared.stream(
            instructions: action.instructions,
            prompt: text
        ) {
            output = snapshot
        }
    }

    /// Long input: one call per paragraph, the result growing a paragraph at a time. Only rewrites
    /// take this path — summaries are map-reduce (T2.3).
    private func streamByParagraph(_ action: Action, text: String) async throws {
        try await ParagraphRewriter().run(text, action: action) { step in
            await MainActor.run {
                self.progress = step
                self.output = step.text
            }
        }
    }

    func retry() {
        guard let action else { return }
        run(action)
    }

    func replace() {
        let text = output
        Task {
            do {
                try await WriteBackService.replace(selection: selection, with: text)
                UndoBuffer.shared.record(original: selection.text, result: text, selection: selection)
                onReplaced()
            } catch {
                Self.log.error("replace failed: \(String(describing: error))")
                phase = .failed(UserFacingError(error))
            }
        }
    }

    func copy() {
        copy(output)
    }

    /// The remedy for a model that declined: hand back what the user selected, unchanged.
    func copyOriginal() {
        copy(selection.text)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onClose()
    }

    func cancel() {
        generation?.cancel()
        generation = nil
        progress = nil
        phase = .actions
    }
}
