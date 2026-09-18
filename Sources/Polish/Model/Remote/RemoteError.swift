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
            let lowered = body.lowercased()
            if lowered.contains("context_length_exceeded") || lowered.contains("maximum context length") {
                return .contextLengthExceeded
            }
            if lowered.contains("model_not_found") || lowered.contains("does not exist") {
                return .modelNotFound
            }
            return .serverError
        default:
            return .serverError
        }
    }
}
