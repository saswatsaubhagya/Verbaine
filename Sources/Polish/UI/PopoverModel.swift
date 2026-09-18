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
    /// "Part 3 of 8" while a long rewrite or summary runs, `nil` for a single-pass action.
    private(set) var progress: PartProgress?
    /// Size of the selection, shown on the action grid; `nil` until it has been measured (T2.4).
    private(set) var estimate: SizeEstimate?
    /// Dismisses the popover: Esc, Copy, or a failure the user closes.
    var onClose: () -> Void = {}
    /// Dismisses the popover and hands over to the undo toast (T1.5).
    var onReplaced: () -> Void = {}

    private var generation: Task<Void, Never>?

    init(selection: Selection) {
        self.selection = selection
    }

    /// Measures the selection so the grid can say how long this will take and hide the actions
    /// that are a bad deal past 12,000 tokens. Silent on failure — an unmeasurable selection just
    /// shows no estimate, and `run` surfaces the real error a moment later.
    func loadEstimate() async {
        guard estimate == nil else { return }
        let budget = TokenBudget()
        guard
            let tokens = try? await ModelService.shared.tokenCount(for: selection.text),
            let limit = try? await budget.maxSinglePassInputTokens(for: .improve)
        else { return }
        estimate = SizeEstimate.make(
            tokens: tokens,
            paragraphs: TextChunker.paragraphs(selection.text).count,
            singlePassLimit: limit
        )
    }

    var diff: [DiffEngine.Segment] {
        DiffEngine.diff(original: selection.text, result: output)
    }

    func run(_ action: Action) {
        guard estimate?.isEnabled(action) ?? true else { return }
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
                if try await TokenBudget().fitsInOnePass(action: action, text: selection.text) {
                    try await streamSinglePass(action, text: selection.text)
                } else if action == .summarize {
                    try await runMapReduce(action, text: selection.text)
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

    /// Long input: one call per paragraph, the result growing a paragraph at a time. Everything
    /// but Summarize takes this path — Shorten included, because shortening paragraph by paragraph
    /// keeps the facts a map-reduce would throw away.
    private func streamByParagraph(_ action: Action, text: String) async throws {
        try await ParagraphRewriter().run(text, action: action, onPart: publish)
    }

    /// Long input, Summarize: a summary per chunk, then a summary of those. Intermediate summaries
    /// show in the pane so the user sees movement; the last step replaces them with the answer.
    private func runMapReduce(_ action: Action, text: String) async throws {
        try await MapReduceSummarizer().run(text, action: action, onPart: publish)
    }

    @Sendable
    private func publish(_ step: PartProgress) async {
        await MainActor.run {
            self.progress = step
            self.output = step.text
        }
    }

    /// Waits for the task `run` started. The silent hotkey path (T3.2) has no view observing
    /// `phase`, so it awaits this and then reads the outcome.
    func wait() async {
        await generation?.value
    }

    func retry() {
        guard let action else { return }
        run(action)
    }

    func replace() {
        Task { await replaceAndWait() }
    }

    /// The body of `replace`, awaitable for the silent hotkey path.
    func replaceAndWait() async {
        let text = output
        do {
            try await WriteBackService.replace(selection: selection, with: text)
            UndoBuffer.shared.record(original: selection.text, result: text, selection: selection)
            onReplaced()
        } catch {
            Self.log.error("replace failed: \(String(describing: error))")
            phase = .failed(UserFacingError(error))
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
