import Foundation

/// Anything that can answer one prompt. `ModelService` is the on-device one; tests stub it so they
/// run on machines without Apple Intelligence.
protocol TextGenerating: Sendable {
    func respond(instructions: String, prompt: String) async throws -> String
}

/// Anything that can measure tokens. `ModelService` measures exactly, via the framework's own
/// tokenizer; a remote provider can only estimate.
protocol TokenCounting: Sendable {
    func tokenCount(for text: String) async throws -> Int
}

/// One whole inference backend: the on-device model, or a user-configured remote endpoint.
///
/// The two protocols above stay separate because `TokenBudget` and `ParagraphRewriter` are tested
/// against tiny stubs that have no business implementing a whole backend.
protocol InferenceProvider: TextGenerating, TokenCounting, Sendable {
    /// Whether this provider will answer right now. Cheap and safe to poll from the UI.
    var availability: ModelAvailability { get }
    /// The full context window in tokens.
    var contextSize: Int { get }
    /// True when using this provider sends the user's text off the Mac. Drives the menu-bar symbol
    /// and the popover badge — the user must never be unsure which one is running.
    var isRemote: Bool { get }
    /// What the popover calls this provider, e.g. "Apple on-device" or "gpt-4o-mini".
    var displayName: String { get }

    func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error>
}
