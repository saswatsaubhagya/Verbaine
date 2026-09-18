import Foundation
import FoundationModels

/// The T2.5 backstop: when the model rejects a piece as too big for its window, split that piece in
/// half and run each half once.
///
/// `TokenBudget` measures before every call, so this should never fire — but the measurement and the
/// model's own accounting are not the same code, and "never truncate silently" means a miss has to
/// cost a retry, not the user's text.
enum ContextRetry {
    /// True if `error` is the framework's "prompt did not fit the window" error, in either of the
    /// two vocabularies `UserFacingError` maps.
    static func isContextSizeExceeded(_ error: any Error) -> Bool {
        if #available(macOS 27.0, *), let error = error as? LanguageModelError {
            if case .contextSizeExceeded = error { return true }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error { return true }
        }
        return false
    }

    /// Runs `respond` on `piece`; on a context-size error, halves `piece` and runs each half once,
    /// joining the two answers.
    ///
    /// ponytail: one retry level only, per the task — a half that still does not fit throws, and the
    /// error reaches the user through `UserFacingError` as it did before.
    static func run(
        _ piece: String,
        _ respond: (String) async throws -> String
    ) async throws -> String {
        do {
            return try await respond(piece)
        } catch {
            guard isContextSizeExceeded(error), let halves = halve(piece) else { throw error }
            let first = try await respond(halves.0)
            let second = try await respond(halves.1)
            return (first.trimmingCharacters(in: .whitespacesAndNewlines) + " "
                + second.trimmingCharacters(in: .whitespacesAndNewlines))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Splits `text` into two roughly equal parts on a sentence boundary, falling back to words for
    /// a single huge sentence. `nil` when there is nothing left to split.
    static func halve(_ text: String) -> (String, String)? {
        let sentences = TextChunker.sentences(text)
        if sentences.count >= 2 {
            let cut = sentences.count / 2
            return (sentences[..<cut].joined(separator: " "), sentences[cut...].joined(separator: " "))
        }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return nil }
        let cut = words.count / 2
        return (words[..<cut].joined(separator: " "), words[cut...].joined(separator: " "))
    }
}
