import AppKit
import ApplicationServices
import os

/// Puts a rewrite back where the selection came from, by pasting it.
///
/// Pasting rather than writing `kAXValueAttribute` is load-bearing (PRD "Technical
/// architecture"): `AXValue` writes fail outright in Slack and browsers, and where they work
/// they blow away the host app's undo stack. A synthetic ⌘V is indistinguishable from the user
/// typing it, so ⌘Z in the source app restores the original.
@MainActor
enum WriteBackService {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "WriteBackService")

    /// How long to leave the result on the clipboard before restoring the user's own contents.
    /// The paste is asynchronous — the app reads the pasteboard on its own event loop — so the
    /// snapshot cannot go back immediately. 300 ms is the budget T0.5 sets.
    private static let restoreDelay = Duration.milliseconds(300)

    /// Marks our clipboard write as machine-generated, so clipboard managers skip it.
    /// De facto standard: http://nspasteboard.org
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Replaces `selection` in its source app with `text`.
    ///
    /// Aborts with `.focusChanged` rather than pasting into the wrong place: between capture and
    /// here the user may have clicked elsewhere, and a ⌘V is unconditional — whatever is focused
    /// receives it.
    static func replace(selection: Selection, with text: String) async throws(WriteBackError) {
        guard AccessibilityPermission.isTrusted else { throw .accessibilityNotTrusted }

        try await activateSourceAppIfNeeded(selection)
        try verifyFocusUnchanged(selection)

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setData(Data(), forType: transientType)
        pasteboard.setString(text, forType: .string)

        SyntheticKeystroke.postCommandV()

        try? await Task.sleep(for: restoreDelay)
        snapshot.restore(to: pasteboard)
    }

    /// Brings the source app back to the front if Polish (or its popover) took focus, and waits
    /// for the switch to land — ⌘V posted mid-switch goes to whoever is frontmost at that
    /// instant, which may still be us.
    private static func activateSourceAppIfNeeded(_ selection: Selection) async throws(WriteBackError) {
        guard let bundleID = selection.appBundleID else { throw .focusChanged }
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != bundleID else { return }

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated })
        else {
            throw .sourceAppGone
        }

        app.activate()

        // Poll rather than trust `activate()`'s return value: it reports that the request was
        // made, not that the app is frontmost yet.
        let deadline = ContinuousClock.now + Duration.milliseconds(500)
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        log.error("\(bundleID) did not come to the front")
        throw .focusChanged
    }

    /// The guard T0.5 asks for: frontmost app and focused element must match capture time.
    private static func verifyFocusUnchanged(_ selection: Selection) throws(WriteBackError) {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard isSameApp(captured: selection.appBundleID, current: frontmost) else {
            log.error("frontmost is \(frontmost ?? "nil"), captured \(selection.appBundleID ?? "nil")")
            throw .focusChanged
        }

        // Clipboard captures have no element to compare — the app did not answer AX in the first
        // place. The bundle-id check is all the verification available on that path.
        guard let captured = selection.element else { return }
        guard let current = focusedElement(ofAppWith: selection.appBundleID),
              CFEqual(captured, current)
        else {
            log.error("focused element changed since capture")
            throw .focusChanged
        }
    }

    /// Whether the app in front now is the app the text came from. Pure, so this half of the
    /// guard is unit-testable; the element half needs a live AX tree.
    static func isSameApp(captured: String?, current: String?) -> Bool {
        guard let captured, let current else { return false }
        return captured == current
    }

    private static func focusedElement(ofAppWith bundleID: String?) -> AXUIElement? {
        guard let bundleID,
              let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
        else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &raw
        ) == .success else { return nil }
        return raw as! AXUIElement?
    }
}
