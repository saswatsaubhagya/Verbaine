import AppKit
import ApplicationServices
import os

/// Reads the current selection out of the frontmost app through the Accessibility API.
///
/// This is the preferred capture path: it is read-only, does not touch the user's clipboard and
/// gives us on-screen bounds to anchor the popover. Apps that do not answer (Electron and most
/// Chromium shells) fall through to `ClipboardSelectionReader` in T0.4.
///
/// `@MainActor` because an `AXUIElement` is not `Sendable` and every call here is a synchronous
/// IPC round-trip to another process; keeping them on one actor keeps the ordering obvious.
@MainActor
enum AXSelectionReader {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "AXSelectionReader")

    /// Reads the selection from whichever app is frontmost right now.
    static func read() throws(CaptureError) -> Selection {
        guard AccessibilityPermission.isTrusted else { throw .accessibilityNotTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw .noFrontmostApp }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused: AXUIElement = copyAttribute(appElement, kAXFocusedUIElementAttribute) else {
            throw .noFocusedElement
        }

        guard let text: String = copyAttribute(focused, kAXSelectedTextAttribute), !text.isEmpty else {
            throw .emptySelection
        }

        return Selection(
            text: text,
            bounds: bounds(of: focused),
            appBundleID: app.bundleIdentifier,
            element: focused,
            source: .accessibility
        )
    }

    /// Screen rect of the selected range, or `nil` if the app does not implement either the
    /// range or the bounds-for-range attribute. Plenty of apps implement one and not the other.
    private static func bounds(of element: AXUIElement) -> CGRect? {
        guard let rangeValue: AXValue = copyAttribute(element, kAXSelectedTextRangeAttribute) else {
            return nil
        }

        var raw: AnyObject?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &raw
        )
        guard status == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID() else {
            log.debug("no bounds for range: \(status.rawValue)")
            return nil
        }

        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgRect else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Typed wrapper over `AXUIElementCopyAttributeValue`. Returns `nil` for every failure —
    /// the caller cannot do anything different for "attribute unsupported" vs "app is busy".
    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw as? T
    }
}
