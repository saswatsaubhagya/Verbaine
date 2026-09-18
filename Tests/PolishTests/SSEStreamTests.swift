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

// MARK: - F1: an in-band error at HTTP 200

@Test("an in-band error frame is read as a failure, not as noise")
func readsInBandError() {
    let line = #"data: {"error":{"message":"insufficient_quota","code":"insufficient_quota"}}"#
    #expect(SSEStream.event(from: line) == .error)
}

@Test("a frame that carries both an error and no choices is still read as a failure")
func readsInBandErrorWithoutChoices() {
    let line = #"data: {"error":{"message":"model overloaded"}}"#
    #expect(SSEStream.event(from: line) == .error)
}

@Test("an in-band error ends the snapshot stream as a thrown failure, never a silent empty answer")
func inBandErrorFrameThrowsFromSnapshots() async throws {
    let lines = StubLines(lines: [
        #"data: {"error":{"message":"insufficient_quota"}}"#,
    ])

    await #expect(throws: RemoteError.self) {
        for try await _ in SSEStream.snapshots(lines: lines) {}
    }
}

@Test("content already streamed before an in-band error still surfaces the error, not a partial success")
func inBandErrorAfterSomeContentStillThrows() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"Fix "}}]}"#,
        #"data: {"error":{"message":"rate limit exceeded"}}"#,
    ])

    await #expect(throws: RemoteError.self) {
        for try await _ in SSEStream.snapshots(lines: lines) {}
    }
}
