#if DEBUG
import SwiftUI
import os

/// Scratch menu for the Phase 0 spike. Every entry here exists to satisfy a task's "Done when"
/// by hand; none of it ships. Delete the whole file once Phase 0 closes (T0.6).
struct DebugMenu: View {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "Debug")

    var body: some View {
        Menu("Debug") {
            Button("Model availability") {
                Self.log.debug("availability: \(String(describing: ModelService.shared.availability))")
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
        }
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
            let result = try await ModelService.shared.respond(
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
