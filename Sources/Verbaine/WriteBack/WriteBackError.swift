/// Why a rewrite could not be put back. `UserFacingError` (T1.6) turns these into sentences.
enum WriteBackError: Error, Equatable {
    /// Accessibility permission has not been granted, so ⌘V cannot be posted.
    case accessibilityNotTrusted
    /// The app the text came from is no longer running.
    case sourceAppGone
    /// A different app is frontmost, or the caret moved to a different element, since capture.
    /// Pasting now would overwrite text the user never selected, so we refuse.
    case focusChanged
}
