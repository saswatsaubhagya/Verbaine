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
    private let log = Logger(subsystem: "com.saswat.polish", category: "RemoteProvider")

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
                        delegate: RedirectSanitizingDelegate(originalHost: request.url?.host())
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

/// The redirect check the wire request needs: `Authorization` rides along with a same-host
/// redirect, and is dropped the moment the host changes.
///
/// Factored out as a pure function, independent of `URLSessionTaskDelegate`, so the actual
/// decision is testable without a socket. A mistyped or hostile base URL must never be able to
/// hand the user's API key to a third party via a redirect — `URLSession` forwards headers
/// across redirects, including cross-host ones, unless something here stops it.
enum RedirectPolicy {
    static func sanitizedRequest(originalHost: String?, redirectedTo request: URLRequest) -> URLRequest {
        guard request.url?.host() != originalHost else { return request }
        var sanitized = request
        sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        return sanitized
    }
}

/// Applies `RedirectPolicy` to every redirect `URLSession` follows for one request. Created fresh
/// per request — it is one small, stateless piece of glue, not a reason to restructure the
/// provider around a session-wide delegate.
private final class RedirectSanitizingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let originalHost: String?

    init(originalHost: String?) {
        self.originalHost = originalHost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        RedirectPolicy.sanitizedRequest(originalHost: originalHost, redirectedTo: request)
    }
}
