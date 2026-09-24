/// Why a capture produced no text. `UserFacingError` (T1.6) turns these into sentences.
enum CaptureError: Error, Equatable {
    /// Accessibility permission has not been granted to Verbaine.
    case accessibilityNotTrusted
    /// No app is frontmost — normally means Verbaine itself is, or the Finder desktop is.
    case noFrontmostApp
    /// The frontmost app reports no focused element; nothing to read from.
    case noFocusedElement
    /// There is a focused element but nothing is selected in it.
    case emptySelection
    /// ⌘C was posted but the app never wrote to the pasteboard in time.
    case clipboardCopyTimedOut
}
