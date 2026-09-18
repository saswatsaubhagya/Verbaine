import AppKit
import os

/// The one entry point for "what has the user selected right now".
///
/// Accessibility first — read-only, gives bounds, leaves the clipboard alone. The ⌘C fallback
/// runs when AX cannot work: apps on `electronFallbackList` (known not to implement
/// `kAXSelectedTextAttribute`), and any app that answers with nothing.
@MainActor
enum SelectionCapture {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "SelectionCapture")

    /// Apps whose selections only come back via ⌘C. Electron and Chromium shells expose an AX
    /// tree but not the selected-text attribute, so AX would report `emptySelection` forever.
    /// T1.8 makes this list editable in Settings; hard-coded is enough for the spike.
    static let electronFallbackList: Set<String> = [
        "com.tinyspeck.slackmacgap",   // Slack
        "com.hnc.Discord",             // Discord
        "com.microsoft.VSCode",        // VS Code
        "com.google.Chrome",
        "company.thebrowser.Browser",  // Arc
        "com.figma.Desktop",
    ]

    /// Reads the current selection, choosing the capture path per app.
    static func capture() async throws(CaptureError) -> Selection {
        guard AccessibilityPermission.isTrusted else { throw .accessibilityNotTrusted }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if prefersClipboard(bundleID: bundleID) {
            log.debug("clipboard path for \(bundleID ?? "unknown")")
            return try await ClipboardSelectionReader.read()
        }

        do {
            return try AXSelectionReader.read()
        } catch .emptySelection, .noFocusedElement {
            // The app either has no selection or does not expose one; ⌘C tells us which.
            log.debug("AX returned nothing for \(bundleID ?? "unknown"); trying clipboard")
            return try await ClipboardSelectionReader.read()
        }
    }

    /// Whether this app is known to need the ⌘C path. Pure, so T0.4's only unit test covers it.
    static func prefersClipboard(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return electronFallbackList.contains(bundleID)
    }
}
