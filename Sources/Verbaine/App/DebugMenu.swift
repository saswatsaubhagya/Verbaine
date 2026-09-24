#if DEBUG
import SwiftUI
import os

/// Scratch menu for the Phase 0 spike. Every entry here exists to satisfy a task's "Done when"
/// by hand; none of it ships. Delete the whole file once Phase 0 closes (T0.6).
struct DebugMenu: View {
    private static let log = Logger(subsystem: "in.saswatsaubhagya.verbaine", category: "Debug")

    var body: some View {
        Menu("Debug") {
            Button("Model availability") {
                Self.log.debug("availability: \(String(describing: Inference.current.availability))")
            }
            Button("Fix grammar sample (T0.2)") {
                Task { await Self.runGrammarSample() }
            }
            Button("Read AX selection (T0.3)") {
                Self.logAXSelection()
            }
            Button("Capture selection (T0.4)") {
                Task { await Self.logCapture() }
            }
            Button("Improve selection (T0.5)") {
                Task { await Self.improveSelection() }
            }
            Button("Show popover over a sample selection") {
                PopoverController.show(selection: Self.sampleSelection)
            }
            Button("Show undo toast") {
                UndoToast.show(near: Self.sampleSelection)
            }
            Button("Show onboarding (T1.7)") {
                OnboardingWindow.show()
            }
            Button("Reset onboarding flag (T1.7)") {
                OnboardingFlag.reset()
            }
            Menu("Errors (T1.6)") {
                ForEach(DebugErrors.all, id: \.name) { sample in
                    Button(sample.name) {
                        PopoverController.show(error: UserFacingError(sample.error))
                    }
                }
                Divider()
                ForEach(DebugErrors.unavailable, id: \.name) { sample in
                    Button(sample.name) {
                        guard let error = UserFacingError(sample.availability) else { return }
                        PopoverController.show(error: error)
                    }
                }
            }
        }
    }

    /// The board's own sample text, so the popover can be checked against `docs/DESIGN.md`
    /// without hunting for a real selection in another app.
    @MainActor
    private static var sampleSelection: Selection {
        Selection(
            text: """
                Hey team, just wanted to circle back on the deploy window that we talked about \
                yesterday. I think we should probably push it to Thursday because the QA run \
                isn't finished yet and I don't want to risk breaking anything over the weekend.
                """,
            bounds: NSScreen.main.map { CGRect(x: $0.frame.midX - 200, y: 260, width: 400, height: 60) },
            appBundleID: "com.tinyspeck.slackmacgap",
            element: nil,
            source: .clipboard
        )
    }

    /// Exercises the facade: AX where it works, ⌘C where it does not.
    @MainActor
    private static func logCapture() async {
        do {
            let selection = try await SelectionCapture.capture()
            log.debug("""
                source=\(String(describing: selection.source)) \
                app=\(selection.appBundleID ?? "nil") \
                text=\(selection.text)
                """)
        } catch {
            log.error("capture failed: \(String(describing: error))")
        }
    }

    /// The whole hero flow end to end: capture, model, paste back.
    @MainActor
    private static func improveSelection() async {
        do {
            let selection = try await SelectionCapture.capture()
            let result = try await Inference.current.respond(
                instructions: "Correct the spelling and grammar. Return only the corrected text, no preamble.",
                prompt: selection.text
            )
            try await WriteBackService.replace(selection: selection, with: result)
            log.debug("replaced \(selection.text) with \(result)")
        } catch {
            log.error("improve failed: \(String(describing: error))")
        }
    }

    @MainActor
    private static func logAXSelection() {
        guard AccessibilityPermission.isTrusted else {
            log.error("not trusted; opening Settings")
            AccessibilityPermission.requestTrust()
            AccessibilityPermission.openSettingsPane()
            return
        }

        do {
            let selection = try AXSelectionReader.read()
            log.debug("""
                app=\(selection.appBundleID ?? "nil") \
                bounds=\(selection.bounds.map(NSStringFromRect) ?? "nil") \
                text=\(selection.text)
                """)
        } catch {
            log.error("AX capture failed: \(String(describing: error))")
        }
    }

    private static func runGrammarSample() async {
        let sample = "I has a apple"
        await ModelService.shared.logBudget(for: sample)

        let start = ContinuousClock.now
        do {
            let result = try await Inference.current.respond(
                instructions: "Correct the spelling and grammar. Return only the corrected text, no preamble.",
                prompt: sample
            )
            log.debug("\(sample) -> \(result) in \(start.duration(to: .now).formatted())")
        } catch {
            log.error("sample failed: \(error.localizedDescription)")
        }
    }
}
#endif
