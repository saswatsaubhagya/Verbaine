import Testing
@testable import Verbaine

@MainActor
@Test("Electron and Chromium apps take the clipboard path", arguments: [
    "com.tinyspeck.slackmacgap",
    "com.microsoft.VSCode",
    "com.google.Chrome",
])
func prefersClipboardForElectronApps(bundleID: String) {
    #expect(SelectionCapture.prefersClipboard(bundleID: bundleID))
}

@MainActor
@Test("native apps and unknown apps try Accessibility first", arguments: [
    "com.apple.Notes",
    "com.apple.mail",
    "com.apple.Safari",
    nil,
] as [String?])
func prefersAccessibilityOtherwise(bundleID: String?) {
    #expect(!SelectionCapture.prefersClipboard(bundleID: bundleID))
}
