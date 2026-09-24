import AppKit
import os

/// Captures the frontmost app's selection by copying it: snapshot the clipboard, press ⌘C for
/// the user, read what landed, put the old clipboard back.
///
/// This is the fallback path for apps that do not answer the Accessibility API — Electron and
/// Chromium shells, which is most of where people actually write (Slack, Chrome, VS Code).
/// It is second choice because it is destructive by nature: every failure mode here has to end
/// with the user's own clipboard restored.
@MainActor
enum ClipboardSelectionReader {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "ClipboardSelectionReader")

    /// How long to wait for the copied text to show up before giving up. Slack answers in
    /// ~30 ms locally; 300 ms is the budget T0.4 sets for a slow app under load.
    private static let timeout = Duration.milliseconds(300)
    /// Poll interval while waiting. Short enough to stay invisible, long enough not to spin.
    private static let pollInterval = Duration.milliseconds(10)

    /// Reads the selection of whichever app is frontmost, via ⌘C.
    static func read() async throws(CaptureError) -> Selection {
        guard AccessibilityPermission.isTrusted else { throw .accessibilityNotTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw .noFrontmostApp }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(of: pasteboard)
        defer { snapshot.restore(to: pasteboard) }

        let changeCountBeforeCopy = pasteboard.changeCount
        SyntheticKeystroke.postCommandC()

        guard let text = await waitForCopiedText(on: pasteboard, after: changeCountBeforeCopy) else {
            throw .clipboardCopyTimedOut
        }
        guard !text.isEmpty else { throw .emptySelection }

        return Selection(
            text: text,
            // No bounds on this path: if the app had answered AX we would not be here. The
            // popover falls back to the mouse location.
            bounds: nil,
            appBundleID: app.bundleIdentifier,
            element: nil,
            source: .clipboard
        )
    }

    /// Polls `changeCount` until the target app has written its copy, then returns the string.
    /// `nil` means the app never answered — no selection, or the copy was swallowed.
    private static func waitForCopiedText(
        on pasteboard: NSPasteboard,
        after changeCountBeforeCopy: Int
    ) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            // Only trust a string that arrived *after* our ⌘C; otherwise we would happily
            // return whatever the user had copied earlier and call it their selection.
            if pasteboard.changeCount != changeCountBeforeCopy {
                return pasteboard.string(forType: .string)
            }
            try? await Task.sleep(for: pollInterval)
        }
        log.debug("no pasteboard change within \(timeout.description)")
        return nil
    }
}
