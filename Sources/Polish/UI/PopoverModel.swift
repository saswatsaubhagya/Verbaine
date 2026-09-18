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
        case failed(String)
    }

    private static let log = Logger(subsystem: "com.saswat.polish", category: "Popover")

    let selection: Selection
    private(set) var phase: Phase = .actions
    private(set) var output = ""
    private(set) var action: Action?
    /// Set after a successful Replace so the view can dismiss; T1.5 turns this into the toast.
    var onClose: () -> Void = {}

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
                // ponytail: raw message until T1.6 maps errors to UserFacingError.
                Self.log.error("generation failed: \(String(describing: error))")
                phase = .failed(error.localizedDescription)
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
                onClose()
            } catch {
                Self.log.error("replace failed: \(String(describing: error))")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
        onClose()
    }

    func cancel() {
        generation?.cancel()
        generation = nil
    }
}
