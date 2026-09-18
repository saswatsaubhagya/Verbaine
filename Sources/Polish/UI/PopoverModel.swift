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

        generation = Task { [selection] in
            do {
                for try await snapshot in await ModelService.shared.stream(
                    instructions: action.instructions,
                    prompt: selection.text
                ) {
                    output = snapshot
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
    }
}
