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
