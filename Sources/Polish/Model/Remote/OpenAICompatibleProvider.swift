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
        var answer = ""
        for try await snapshot in stream(instructions: instructions, prompt: prompt) {
            answer = snapshot
        }
        guard !answer.isEmpty else { throw RemoteError.malformedResponse }
        return answer
    }

    func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(instructions: instructions, prompt: prompt)
                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // The body carries the only thing that tells three different 400s apart.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw RemoteError.from(status: http.statusCode, body: body)
                    }

                    for try await snapshot in SSEStream.snapshots(lines: bytes.lines) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
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
