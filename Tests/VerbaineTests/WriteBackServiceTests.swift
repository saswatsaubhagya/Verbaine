import Testing
@testable import Verbaine

@MainActor
@Test("the same frontmost app passes the focus guard")
func sameAppPassesGuard() {
    #expect(WriteBackService.isSameApp(captured: "com.apple.Notes", current: "com.apple.Notes"))
}

@MainActor
@Test("a different frontmost app fails the focus guard", arguments: [
    ("com.apple.Notes", "com.tinyspeck.slackmacgap"),
    ("com.apple.Notes", "in.saswatsaubhagya.verbaine"),
])
func differentAppFailsGuard(captured: String, current: String) {
    #expect(!WriteBackService.isSameApp(captured: captured, current: current))
}

@MainActor
@Test("an unknown bundle id on either side fails the focus guard", arguments: [
    (nil, "com.apple.Notes"),
    ("com.apple.Notes", nil),
    (nil, nil),
] as [(String?, String?)])
func unknownBundleIDFailsGuard(captured: String?, current: String?) {
    // Cannot verify what we cannot name: pasting blind could overwrite anything.
    #expect(!WriteBackService.isSameApp(captured: captured, current: current))
}
