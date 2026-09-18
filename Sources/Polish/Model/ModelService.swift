import FoundationModels
import Foundation
import os

/// Serialises every call to the on-device model.
///
/// One fresh `LanguageModelSession` per request, deliberately: no transcript is carried between
/// actions, so each action gets the whole context window and nothing a user wrote earlier can
/// leak into a later rewrite.
actor ModelService: InferenceProvider {
    static let shared = ModelService()

    private let model = SystemLanguageModel.default
    private let log = Logger(subsystem: "com.saswat.polish", category: "ModelService")

    /// Whether the model will answer right now. Cheap and safe to poll from the UI.
    nonisolated var availability: ModelAvailability {
        ModelAvailability(model.availability)
    }

    /// The full context window in tokens. Never assume 4096 — it varies by OS version and device.
    nonisolated var contextSize: Int {
        model.contextSize
    }

    /// The on-device model is the reason this app exists: nothing it is given leaves the Mac.
    nonisolated var isRemote: Bool { false }

    nonisolated var displayName: String { "Apple on-device" }

    func tokenCount(for text: String) async throws -> Int {
        try await model.tokenCount(for: text)
    }

    /// Runs one action against the model and returns the whole answer.
    ///
    /// - Parameters:
    ///   - instructions: the action's system prompt, from `Prompts.swift`.
    ///   - prompt: the user's selected text.
    func respond(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()

        let start = ContinuousClock.now
        let response = try await session.respond(to: prompt)
        log.debug("respond took \(start.duration(to: .now).formatted())")

        return response.content
    }

    /// Streams one action's answer. Each element is the whole answer so far, not a delta —
    /// `ResponseStream` emits cumulative snapshots, and the result pane rebinds the whole string
    /// anyway. Cancelling the iteration cancels the generation.
    nonisolated func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Logs the context window and what a sample string costs against it. Debug builds only.
    func logBudget(for sample: String) async {
        do {
            let tokens = try await tokenCount(for: sample)
            log.debug("contextSize=\(self.contextSize) tokens=\(tokens) for \(sample.count) characters")
        } catch {
            log.error("tokenCount failed: \(error.localizedDescription)")
        }
    }
}
