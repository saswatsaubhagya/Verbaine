import AppKit
import ApplicationServices

/// Whether Verbaine is allowed to read other apps' selections, and how to ask.
///
/// Every AX call in `AXSelectionReader` silently returns `kAXErrorAPIDisabled` without this, so
/// the UI checks here first and says "grant Accessibility" rather than "no text selected".
enum AccessibilityPermission {
    /// Already granted? Never prompts.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's "allow Verbaine to control this computer" alert, once per app install.
    /// Returns the trust state as of right now — granting it happens later, in System Settings.
    @discardableResult
    static func requestTrust() -> Bool {
        // The constant itself is a global `var` and so off-limits under strict concurrency;
        // the string it holds is API and has never changed.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility, where the user flips the switch.
    static func openSettingsPane() {
        // ponytail: hard-coded URL because there is no API for this pane; it has been stable
        // since the System Preferences era and fails soft (Settings just opens at the top).
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
