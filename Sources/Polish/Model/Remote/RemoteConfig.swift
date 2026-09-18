import Foundation

/// Which backend runs the actions. Raw values persist in `UserDefaults`.
enum InferenceProviderKind: String, CaseIterable, Sendable, Identifiable {
    case apple, remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple on-device"
        case .remote: "Custom endpoint"
        }
    }
}

/// Where a remote provider lives and what to ask it for. The API key is deliberately not here —
/// it lives in the Keychain, via `APIKeyStore`, and nothing in this struct is secret.
struct RemoteConfig: Equatable, Sendable {
    /// e.g. `https://api.openai.com/v1`. Stored as typed, validated on use.
    var baseURL: String
    /// e.g. `gpt-4o-mini`. Free text: every endpoint names its models differently, and some have
    /// no way to list them.
    var model: String
    /// What the user says this model's window is. Declared rather than discovered — no
    /// OpenAI-compatible endpoint reports it.
    var contextSize: Int

    static let defaultContextSize = 128_000

    /// Enough filled in to be worth trying. The key is checked separately, at call time, because
    /// it is keyed by host and the host comes from `baseURL`.
    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The host the API key is filed under, so switching endpoints cannot silently reuse another
    /// endpoint's key.
    var host: String? {
        URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host()
    }

    /// The chat-completions URL. `nil` when `baseURL` is not a URL at all.
    var endpointURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host() != nil else { return nil }
        return url.appending(path: "chat/completions")
    }
}
