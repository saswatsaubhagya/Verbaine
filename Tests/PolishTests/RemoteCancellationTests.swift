import Foundation
import Testing
@testable import Polish

/// F2: cancelling the task that is draining a remote stream must surface as a cancellation, not
/// as a truncated success.
///
/// `AsyncThrowingStream` has a sharp edge: when the task calling `next()` is cancelled, iteration
/// ends quietly — the `for try await` loop just stops, exactly as if the producer had finished
/// normally — no matter what the producer eventually passes to `finish`. These tests exercise
/// `OpenAICompatibleProvider.drain` directly against a bare, hand-built stream, so the fix is
/// checked without any network involved.
private func partialAnswerStream() -> AsyncThrowingStream<String, any Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            continuation.yield("Fix ")
            try? await Task.sleep(for: .milliseconds(200))
            continuation.yield("Fix the grammar.")
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

@Test("draining a stream to completion returns its last snapshot")
func drainReturnsFinalSnapshot() async throws {
    #expect(try await OpenAICompatibleProvider.drain(partialAnswerStream()) == "Fix the grammar.")
}

@Test("cancelling the caller mid-stream throws, rather than returning the partial answer as a success")
func drainPropagatesCancellationInsteadOfPartialSuccess() async throws {
    let outer = Task<String, any Error> {
        try await OpenAICompatibleProvider.drain(partialAnswerStream())
    }

    // Give the producer time to yield its first snapshot ("Fix "), then cancel before the
    // second one — the exact shape of a user cancelling mid-rewrite.
    try await Task.sleep(for: .milliseconds(30))
    outer.cancel()

    await #expect(throws: CancellationError.self) {
        _ = try await outer.value
    }
}

@Test("a stream cancelled before it ever yields still throws, not an empty success")
func drainPropagatesCancellationBeforeAnyYield() async throws {
    let neverYields = AsyncThrowingStream<String, any Error> { continuation in
        let task = Task {
            try? await Task.sleep(for: .milliseconds(500))
            continuation.yield("too late")
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }

    let outer = Task<String, any Error> {
        try await OpenAICompatibleProvider.drain(neverYields)
    }
    outer.cancel()

    await #expect(throws: CancellationError.self) {
        _ = try await outer.value
    }
}
