import Foundation
import os

/// One `InferenceProvider` for every endpoint that speaks OpenAI's `/chat/completions` — OpenAI,
/// Anthropic's compatibility layer, OpenRouter, Groq, Together, Ollama, LM Studio, vLLM.
///
/// There is deliberately no per-vendor code: the base URL, the model name and the key come from
/// Settings, and everything else is the same wire format. One request per action, `messages`
/// rebuilt from scratch every time, so no transcript is ever carried between actions.
struct OpenAICompatibleProvider: InferenceProvider {
    private let config: RemoteConfig
    private let apiKey: String
    private let session: URLSession
    private let log = Logger(subsystem: "in.saswatsaubhagya.verbaine", category: "RemoteProvider")

    init(config: RemoteConfig, apiKey: String, session: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
    }

    var isRemote: Bool { true }

    var displayName: String { config.model }

    var contextSize: Int { config.contextSize }

    var availability: ModelAvailability {
        isConfigured ? .ready : .remoteNotConfigured
    }

    private var isConfigured: Bool {
        config.isComplete && config.endpointURL != nil && !apiKey.isEmpty
    }

    /// Four characters per token, the usual English rule of thumb.
    ///
    /// ponytail: an estimate, not a count. Real tokenizers are per-vendor and per-version, and at a
    /// 128k declared window the estimate never changes the single-pass verdict. If a user reports
    /// truncation on a small local model, the upgrade is a bundled BPE table here, nowhere else.
    func tokenCount(for text: String) async throws -> Int {
        text.count / 4
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        let answer = try await Self.drain(stream(instructions: instructions, prompt: prompt))
        guard !answer.isEmpty else { throw RemoteError.malformedResponse }
        return answer
    }

    /// Drains a snapshot stream to its last value, then re-checks the ambient task's own
    /// cancellation state.
    ///
    /// Cancelling the task that is iterating an `AsyncThrowingStream` ends that iteration
    /// quietly — the `for try await` loop just stops, as if the sequence had finished normally,
    /// no matter what the producer eventually passes to `finish`. Left alone, that turns a
    /// cancelled rewrite into a "successful" partial answer, which `ContextRetry` and
    /// `MapReduceSummarizer` would then commit as if it were the whole thing. The explicit check
    /// below is what actually converts that quiet ending back into a thrown `CancellationError`
    /// — factored out here so it is testable with a bare stream, no network involved.
    static func drain(_ stream: AsyncThrowingStream<String, any Error>) async throws -> String {
        var answer = ""
        for try await snapshot in stream { answer = snapshot }
        try Task.checkCancellation()
        return answer
    }

    func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(instructions: instructions, prompt: prompt)
                    let (bytes, response) = try await session.bytes(
                        for: request,
                        delegate: RedirectGuardDelegate(originalURL: request.url)
                    )

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // The body carries the only thing that tells three different 400s apart.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw RemoteError.from(status: http.statusCode, body: body)
                    }

                    var received = false
                    for try await snapshot in SSEStream.snapshots(lines: bytes.lines) {
                        received = true
                        continuation.yield(snapshot)
                    }
                    // A 200 that streamed no content and no in-band error at all — some endpoints
                    // close the connection with nothing rather than answering. Finishing quietly
                    // here would render as an empty "successful" rewrite; that is the silent
                    // truncation the project forbids outright.
                    guard received else { throw RemoteError.malformedResponse }
                    continuation.finish()
                } catch is CancellationError {
                    // Propagate the cancellation itself, not a plain finish — a plain finish reads
                    // to `respond`'s drain as a (possibly partial) success. See `drain` above for
                    // the other half of this fix: this call matters only when the producer itself
                    // observes cancellation before the consumer's own re-check does.
                    continuation.finish(throwing: CancellationError())
                } catch let error as RemoteError {
                    continuation.finish(throwing: error)
                } catch {
                    // Never surface the underlying description: some URLErrors embed the URL, and
                    // a mistyped key can end up in a URL.
                    log.error("remote request failed: \(error._domain) \(error._code)")
                    continuation.finish(throwing: RemoteError.unreachable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(instructions: String, prompt: String) throws -> URLRequest {
        guard isConfigured, let url = config.endpointURL else { throw RemoteError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: any Sendable] = [
            "model": config.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// Whether a redirect should be followed at all.
///
/// Refusing a cross-host redirect outright — rather than only stripping `Authorization` — is
/// what protects the request body too, and that body is the user's selected text: `URLSession`
/// carries the body across a redirect exactly as it carries headers, so stripping only the key
/// would still hand a hostile or mistyped base URL the user's own text on a 307/308. A `nil`
/// original URL (a malformed base URL) never matches anything, including another URL with no
/// host — there being nothing to compare against is always a refusal, not a free pass.
///
/// Factored out as a pure function, independent of `URLSessionTaskDelegate`, so the decision is
/// testable without a socket.
enum RedirectPolicy {
    /// The whole origin has to match, not just the host: a same-host redirect that downgrades
    /// `https` to `http`, or moves to a different port, is a different endpoint and must not
    /// receive the key or the body either. (App Transport Security happens to block the plaintext
    /// hop today, but a guard that depends on something else to hold is not a guard.) Hosts are
    /// compared case-insensitively — DNS names are case-insensitive, so refusing a
    /// case-differing redirect to the same origin fails closed for no reason.
    static func allowsRedirect(original: URL?, to request: URLRequest) -> Bool {
        guard let original, let redirected = request.url,
              let originalHost = original.host(), let redirectedHost = redirected.host(),
              let originalScheme = original.scheme?.lowercased(),
              let redirectedScheme = redirected.scheme?.lowercased()
        else { return false }

        return redirectedHost.lowercased() == originalHost.lowercased()
            && redirectedScheme == originalScheme
            && effectivePort(of: redirected) == effectivePort(of: original)
    }

    /// The port the request actually goes to: the explicit one, or the scheme's default when the
    /// URL leaves it out — so `https://h/x` and `https://h:443/x` are one origin, and
    /// `https://h:8443/x` is not.
    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

/// Applies `RedirectPolicy` to every redirect `URLSession` follows for one request. Created fresh
/// per request — it is one small, stateless piece of glue, not a reason to restructure the
/// provider around a session-wide delegate.
private final class RedirectGuardDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originalURL: URL?

    init(originalURL: URL?) {
        self.originalURL = originalURL
    }

    /// Returning `nil` refuses the redirect outright: `URLSession` hands back the redirect
    /// response itself (a 3xx, read as a `RemoteError` like any other non-200) instead of
    /// following it, so neither `Authorization` nor the request body ever reaches the redirect
    /// target.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        RedirectPolicy.allowsRedirect(original: originalURL, to: request) ? request : nil
    }
}
