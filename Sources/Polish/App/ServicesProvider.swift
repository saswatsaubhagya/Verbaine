import AppKit
import os

/// Right-click → Services → "Polish: Improve" / "Polish: Summarize" in any app.
///
/// The entries live in `Polish-Info.plist` (`NSServices`); `NSMessage` names the selectors below.
/// A Services handler replaces the selection by writing the result back onto the pasteboard it was
/// handed, and the replacement happens when the method *returns* — so the model call cannot be
/// left running in the background, and this blocks the calling thread until it finishes. Blocking
/// is safe here: `ModelService` is an actor with its own executor and never hops to the main
/// actor, so nothing it needs is behind the thread this parks.
final class ServicesProvider: NSObject {
    /// Set on `NSApp.servicesProvider` at launch, which only ever happens on the main actor.
    @MainActor static let shared = ServicesProvider()

    private static let log = Logger(subsystem: "com.saswat.polish", category: "Services")

    /// A single-pass call is ~1 s; past this the model is hung, and a Services item has no way to
    /// show progress or let the user cancel.
    private static let timeout = 60.0

    @objc
    func improveSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        run(.improve, pasteboard: pasteboard, error: error)
    }

    @objc
    func summarizeSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        run(.summarize, pasteboard: pasteboard, error: error)
    }

    private func run(
        _ action: Action,
        pasteboard: NSPasteboard,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard
            let text = pasteboard.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            error.pointee = "Select some text first." as NSString
            return
        }

        // ponytail: single pass only. Long selections come back as the context-size error rather
        // than taking the chunked path — that path reports progress part by part and a Services
        // item has nowhere to show it. The hotkey flow still handles long text.
        let instructions = Prompts.instructions(for: action)
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                box.value = .success(
                    try await ModelService.shared.respond(instructions: instructions, prompt: text)
                )
            } catch {
                box.value = .failure(error)
            }
            done.signal()
        }

        guard done.wait(timeout: .now() + Self.timeout) == .success, let outcome = box.value else {
            error.pointee = "That took too long. Try a shorter selection." as NSString
            return
        }

        switch outcome {
        case .success(let result):
            pasteboard.clearContents()
            pasteboard.setString(result, forType: .string)
        case .failure(let failure):
            Self.log.error("service \(action.id) failed: \(String(describing: failure))")
            error.pointee = UserFacingError(failure).message as NSString
        }
    }

    /// Hands one result across the semaphore. Unchecked because the semaphore, not the compiler,
    /// is what orders the write before the read.
    private final class Box: @unchecked Sendable {
        var value: Result<String, any Error>?
    }
}
