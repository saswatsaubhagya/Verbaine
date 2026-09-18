import Foundation
import Testing
@testable import Polish

@Test("every HTTP status the endpoints actually return maps to its own failure", arguments: [
    (401, RemoteError.unauthorized),
    (403, .unauthorized),
    (404, .modelNotFound),
    (429, .rateLimited),
    (500, .serverError),
    (503, .serverError),
])
func mapsStatus(status: Int, expected: RemoteError) {
    #expect(RemoteError.from(status: status, body: "") == expected)
}

@Test("a 400 naming the model is a model problem, not a generic one")
func mapsModelNotFound() {
    let body = #"{"error":{"message":"The model `gpt-9` does not exist","code":"model_not_found"}}"#
    #expect(RemoteError.from(status: 400, body: body) == .modelNotFound)
}

@Test("a 400 about the window routes into the existing halve-and-retry backstop")
func mapsContextLengthExceeded() {
    let body = #"{"error":{"message":"maximum context length","code":"context_length_exceeded"}}"#
    #expect(RemoteError.from(status: 400, body: body) == .contextLengthExceeded)
    #expect(ContextRetry.isContextSizeExceeded(RemoteError.contextLengthExceeded))
}

@Test("an unrecognised 400 is a server error rather than a silent success")
func mapsUnknown400() {
    #expect(RemoteError.from(status: 400, body: "{}") == .serverError)
}

@Test("every remote failure reaches the user as a sentence and one thing to do", arguments: [
    RemoteError.notConfigured,
    .unauthorized,
    .modelNotFound,
    .rateLimited,
    .serverError,
    .unreachable,
    .malformedResponse,
])
func everyRemoteErrorHasAMessage(error: RemoteError) {
    let shown = UserFacingError(error)
    #expect(!shown.message.isEmpty)
    #expect(shown.message.hasSuffix(".") || shown.message.hasSuffix("?"))
}

@Test("a key problem points the user at the Model tab")
func keyProblemsOpenSettings() {
    #expect(UserFacingError(RemoteError.unauthorized).remedy == .modelSettings)
    #expect(UserFacingError(RemoteError.modelNotFound).remedy == .modelSettings)
    #expect(UserFacingError(RemoteError.notConfigured).remedy == .modelSettings)
}

@Test("a URLSession failure is reported as unreachable, not as a generic retry")
func mapsURLError() {
    let shown = UserFacingError(URLError(.notConnectedToInternet))
    #expect(shown == UserFacingError(RemoteError.unreachable))
}
