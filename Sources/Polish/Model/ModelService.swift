import FoundationModels
import Foundation
import os

/// Serialises every call to the on-device model.
///
/// One fresh `LanguageModelSession` per request, deliberately: no transcript is carried between
/// actions, so each action gets the whole context window and nothing a user wrote earlier can
/// leak into a later rewrite.
actor ModelService {
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
