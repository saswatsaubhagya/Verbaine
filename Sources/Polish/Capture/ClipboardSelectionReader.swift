import AppKit
import Carbon.HIToolbox
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
        let snapshot = Snapshot(of: pasteboard)
        defer { snapshot.restore(to: pasteboard) }

        let changeCountBeforeCopy = pasteboard.changeCount
        postCommandC()

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

    /// Synthesizes ⌘C into the system event stream, which the frontmost app receives as if the
    /// user had typed it. Needs the same Accessibility trust as reading.
    private static func postCommandC() {
        // A private source keeps our synthetic modifiers out of the user's real keyboard state,
        // so a physically held key does not get mixed into the chord.
        let source = CGEventSource(stateID: .privateState)
        let c = CGKeyCode(kVK_ANSI_C)

        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: c, keyDown: isDown) else {
                log.error("could not create ⌘C event")
                return
            }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    /// A copy of the pasteboard's contents, deep enough to survive `clearContents()`.
    ///
    /// `NSPasteboardItem`s belonging to the pasteboard are invalidated when it is cleared, so
    /// every type's data is copied into fresh items up front.
    private struct Snapshot {
        private let items: [NSPasteboardItem]

        init(of pasteboard: NSPasteboard) {
            items = (pasteboard.pasteboardItems ?? []).map { original in
                let copy = NSPasteboardItem()
                for type in original.types {
                    if let data = original.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
        }

        /// Puts the snapshot back. An empty snapshot still clears, so our copy never lingers.
        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }
            pasteboard.writeObjects(items)
        }
    }
}
