import Foundation
import Testing
@testable import Polish

/// Replays a fixed list of lines, as `URLSession.bytes(for:).lines` would deliver them.
private struct StubLines: AsyncSequence, Sendable {
    let lines: [String]

    struct AsyncIterator: AsyncIteratorProtocol {
        var remaining: [String]
        mutating func next() async throws -> String? {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(remaining: lines) }
}

@Test("a content delta is read out of a data line")
func readsContentDelta() {
    let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
    #expect(SSEStream.event(from: line) == .content("Hello"))
}

@Test("the terminator ends the stream")
func readsDone() {
    #expect(SSEStream.event(from: "data: [DONE]") == .done)
}

@Test("noise between events is ignored, never thrown", arguments: [
    "",
    ": keep-alive",
    "event: message",
    #"data: {"choices":[{"delta":{}}]}"#,
    #"data: {"choices":[]}"#,
    "data: not json at all",
])
func ignoresNoise(line: String) {
    #expect(SSEStream.event(from: line) == .ignore)
}

@Test("snapshots are cumulative, matching what the on-device stream yields")
func snapshotsAccumulate() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"Fix "}}]}"#,
        ": keep-alive",
        #"data: {"choices":[{"delta":{"content":"the "}}]}"#,
        #"data: {"choices":[{"delta":{"content":"grammar."}}]}"#,
        "data: [DONE]",
    ])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received == ["Fix ", "Fix the ", "Fix the grammar."])
}

@Test("a stream that ends without [DONE] still finishes with everything it received")
func snapshotsSurviveMissingTerminator() async throws {
    let lines = StubLines(lines: [#"data: {"choices":[{"delta":{"content":"Half"}}]}"#])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received == ["Half"])
}
