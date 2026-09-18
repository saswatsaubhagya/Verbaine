import ApplicationServices
import Foundation

/// One captured selection: what the user highlighted, and enough context to put a rewrite back.
///
/// Not `Sendable` on purpose — `element` is an `AXUIElement` tied to the main thread's AX
/// session, and write-back (T0.5) compares it against the focused element at paste time to
/// catch the user clicking elsewhere mid-rewrite.
struct Selection {
    /// The selected text, exactly as the source app reported it.
    let text: String
    /// Screen rect of the selection, top-left origin (AX coordinates, not AppKit's).
    /// `nil` when the app does not implement the bounds attribute — the popover then falls
    /// back to the mouse location.
    let bounds: CGRect?
    /// Bundle id of the app the text came from, e.g. `com.apple.mail`.
    let appBundleID: String?
    /// The focused element the text was read from, or `nil` for clipboard captures (T0.4).
    let element: AXUIElement?
    /// How the text was captured. Clipboard captures cannot verify the element at paste time.
    let source: Source

    enum Source {
        case accessibility
        case clipboard
    }
}
