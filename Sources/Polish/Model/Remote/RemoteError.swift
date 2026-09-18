import Foundation

/// What a remote endpoint can do to us, in the app's own vocabulary.
///
/// The endpoint is not ours and its error bodies vary, so the HTTP status carries most of the
/// meaning and the body is only consulted to tell three different 400s apart.
enum RemoteError: Error, Equatable {
    /// No base URL, no model name, or no key stored for that host.
    case notConfigured
    case unauthorized
    case modelNotFound
    case rateLimited
    case serverError
    /// Offline, DNS, TLS, timeout — anything `URLSession` itself refused.
    case unreachable
    /// The input did not fit the model's window, per the endpoint. Feeds `ContextRetry`.
    case contextLengthExceeded
    /// A 200 whose body was not a chat completion.
    case malformedResponse

    /// `body` is the raw response text. It is matched case-insensitively and never shown to the
    /// user or logged — some providers echo request content back inside error messages.
    static func from(status: Int, body: String) -> RemoteError {
        switch status {
        case 401, 403:
            return .unauthorized
        case 404:
            return .modelNotFound
        case 429:
            return .rateLimited
        case 400:
            return classify(body: body)
        default:
            return .serverError
        }
    }

    /// Classifies an error body by substring, without any HTTP status to lean on. Used for a
    /// real 400's body, and for an OpenAI-compatible in-band `data:` error frame at HTTP 200 —
    /// OpenRouter, Groq and Together all report failures that way, where the status is always
    /// 200 and carries no information at all. Matched case-insensitively; the body itself is
    /// never shown to the user or logged.
    static func classify(body: String) -> RemoteError {
        let lowered = body.lowercased()
        if lowered.contains("context_length_exceeded") || lowered.contains("maximum context length") {
            return .contextLengthExceeded
        }
        if lowered.contains("model_not_found") || lowered.contains("does not exist") {
            return .modelNotFound
        }
        if lowered.contains("insufficient_quota") || lowered.contains("invalid_api_key")
            || lowered.contains("unauthorized") || lowered.contains("authentication") {
            return .unauthorized
        }
        return .serverError
    }
}
