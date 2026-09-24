import Foundation
import Testing
@testable import Verbaine

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

// MARK: - M1: finish_reason "length" is a truncated answer, not a finished one

@Test("a finish_reason of length is read as a truncation, not as content or noise")
func readsLengthFinishReason() {
    let line = #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#
    #expect(SSEStream.event(from: line) == .finish(content: nil, truncated: true))
}

@Test("a last delta that arrives on the same frame as finish_reason length is still a truncation")
func readsLengthFinishReasonCarryingContent() {
    let line = #"data: {"choices":[{"delta":{"content":"cut"},"finish_reason":"length"}]}"#
    #expect(SSEStream.event(from: line) == .finish(content: "cut", truncated: true))
}

@Test("a finish_reason of stop is a clean end, not a truncation")
func readsStopFinishReason() {
    let line = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
    #expect(SSEStream.event(from: line) == .finish(content: nil, truncated: false))
}

@Test("a null finish_reason on an ordinary content frame changes nothing")
func nullFinishReasonIsOrdinaryContent() {
    let line = #"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#
    #expect(SSEStream.event(from: line) == .content("Hello"))
}

@Test("an answer capped at the endpoint's output limit throws instead of being presented as whole")
func lengthCappedAnswerThrows() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"The first half of the "}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#,
        "data: [DONE]",
    ])

    await #expect(throws: RemoteError.answerTruncated) {
        for try await _ in SSEStream.snapshots(lines: lines) {}
    }
}

@Test("the truncation message names the output limit and sends the user to Settings")
func truncationIsItsOwnUserFacingError() {
    let error = UserFacingError(RemoteError.answerTruncated)
    #expect(error.remedy == .modelSettings)
    #expect(error.message.lowercased().contains("cut off"))
    #expect(error != UserFacingError(RemoteError.malformedResponse))
    #expect(error != UserFacingError(RemoteError.contextLengthExceeded))
}

@Test("a stream that terminates with finish_reason stop and no [DONE] is a clean success")
func finishReasonStopWithoutDoneIsSuccess() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"Whole answer."}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
    ])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received == ["Whole answer."])
}

@Test("a last delta riding along with finish_reason stop is kept, not dropped")
func finalContentOnStopFrameIsKept() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"Whole "}}]}"#,
        #"data: {"choices":[{"delta":{"content":"answer."},"finish_reason":"stop"}]}"#,
    ])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received.last == "Whole answer.")
}

// MARK: - M2: a stream that just stops is a failure, not a success

@Test("a connection that closes mid-answer throws rather than reporting the fragment as whole")
func missingTerminatorThrows() async throws {
    let lines = StubLines(lines: [#"data: {"choices":[{"delta":{"content":"Half"}}]}"#])

    await #expect(throws: RemoteError.incompleteStream) {
        for try await _ in SSEStream.snapshots(lines: lines) {}
    }
}

@Test("an entirely empty stream is a failure too")
func emptyStreamThrows() async throws {
    await #expect(throws: RemoteError.incompleteStream) {
        for try await _ in SSEStream.snapshots(lines: StubLines(lines: [])) {}
    }
}

@Test("the fragment streamed before the connection dropped is still yielded before the throw")
func fragmentIsYieldedBeforeIncompleteStreamThrows() async throws {
    let lines = StubLines(lines: [#"data: {"choices":[{"delta":{"content":"Half"}}]}"#])

    var received: [String] = []
    await #expect(throws: RemoteError.incompleteStream) {
        for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }
    }
    #expect(received == ["Half"])
}

@Test("an incomplete stream gets its own message, distinct from an unreadable reply")
func incompleteStreamIsItsOwnUserFacingError() {
    let error = UserFacingError(RemoteError.incompleteStream)
    #expect(error.remedy == .retry)
    #expect(error != UserFacingError(RemoteError.malformedResponse))
}

// MARK: - F1: an in-band error at HTTP 200

@Test("an in-band error frame is read as a failure, not as noise")
func readsInBandError() {
    let line = #"data: {"error":{"message":"insufficient_quota","code":"insufficient_quota"}}"#
    #expect(SSEStream.event(from: line) == .error(.unauthorized))
}

@Test("a frame that carries both an error and no choices is still read as a failure")
func readsInBandErrorWithoutChoices() {
    let line = #"data: {"error":{"message":"model overloaded"}}"#
    #expect(SSEStream.event(from: line) == .error(.serverError))
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

// MARK: - F4: a null "error" field must not abort a healthy stream

@Test("a null error field alongside valid choices reads as ordinary content, not a failure")
func nullErrorFieldWithValidChoicesReadsAsContent() {
    let line = #"data: {"error":null,"choices":[{"delta":{"content":"Hello"}}]}"#
    #expect(SSEStream.event(from: line) == .content("Hello"))
}

@Test("a stream where every frame carries a null error field still delivers all its content")
func nullErrorFieldDoesNotAbortSnapshots() async throws {
    let lines = StubLines(lines: [
        #"data: {"error":null,"choices":[{"delta":{"content":"Fix "}}]}"#,
        #"data: {"error":null,"choices":[{"delta":{"content":"the grammar."}}]}"#,
        "data: [DONE]",
    ])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received == ["Fix ", "Fix the grammar."])
}

// MARK: - F5: an in-band error is classified, not always a generic server error

@Test("an in-band context-length error routes into the existing halve-and-retry backstop")
func inBandContextLengthErrorIsRetryable() {
    let line = #"data: {"error":{"message":"This model's maximum context length is 4096 tokens","code":"context_length_exceeded"}}"#
    let event = SSEStream.event(from: line)
    #expect(event == .error(.contextLengthExceeded))
    guard case .error(let remoteError) = event else {
        Issue.record("expected an .error event")
        return
    }
    #expect(ContextRetry.isContextSizeExceeded(remoteError))
}

@Test("an in-band quota or auth error points the user at Settings, not at Retry")
func inBandQuotaErrorIsUnauthorized() {
    let line = #"data: {"error":{"message":"You exceeded your current quota","code":"insufficient_quota"}}"#
    let event = SSEStream.event(from: line)
    #expect(event == .error(.unauthorized))
    guard case .error(let remoteError) = event else {
        Issue.record("expected an .error event")
        return
    }
    #expect(UserFacingError(remoteError).remedy == .modelSettings)
}

// MARK: - F7: an "error" field is not always an object

@Test("a string-valued error field is still read as a failure, not as noise")
func readsStringValuedErrorField() {
    let line = #"data: {"error":"insufficient_quota"}"#
    #expect(SSEStream.event(from: line) == .error(.unauthorized))
}

@Test("an array-valued error field is still read as a failure, not as noise")
func readsArrayValuedErrorField() {
    let line = #"data: {"error":["insufficient_quota"]}"#
    guard case .error = SSEStream.event(from: line) else {
        Issue.record("expected an .error event")
        return
    }
}

@Test("content already streamed before a string-valued error still surfaces the error, not a quiet partial success")
func stringValuedErrorAfterContentStillThrows() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"Fix "}}]}"#,
        #"data: {"error":"insufficient_quota"}"#,
    ])

    await #expect(throws: RemoteError.self) {
        for try await _ in SSEStream.snapshots(lines: lines) {}
    }
}
