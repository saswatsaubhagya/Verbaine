import Foundation

/// Turns an OpenAI-compatible server-sent-event stream into the cumulative snapshots the popover
/// already knows how to render.
///
/// ponytail: this parses lines, not bytes. `URLSession.bytes(for:).lines` already reassembles a
/// JSON object split across two network chunks, so there is no buffer to get wrong here.
enum SSEStream {
    enum Event: Equatable {
        case content(String)
        case done
        /// Keep-alives, comments, empty deltas and anything unparseable. A malformed line is never
        /// fatal — the provider is not ours, and one bad frame must not lose the answer so far.
        case ignore
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    static func event(from line: String) -> Event {
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let content = chunk.choices.first?.delta?.content,
              !content.isEmpty
        else { return .ignore }
        return .content(content)
    }

    /// Yields the whole answer so far after every delta — the same contract `ResponseStream` has,
    /// so the result pane and the word-level diff need no remote-specific branch.
    static func snapshots<S: AsyncSequence & Sendable>(
        lines: S
    ) -> AsyncThrowingStream<String, any Error> where S.Element == String, S.AsyncIterator: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var answer = ""
                    for try await line in lines {
                        switch event(from: line) {
                        case .content(let delta):
                            answer += delta
                            continuation.yield(answer)
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
