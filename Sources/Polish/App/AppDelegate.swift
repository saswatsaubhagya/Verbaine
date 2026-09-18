import AppKit
import os

/// Owns the app-lifetime wiring the SwiftUI `Scene` has no place for: the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.start { Task { await AppDelegate.trigger() } }
        OnboardingWindow.showIfNeeded()
    }

    /// The single entry point for "user asked to polish the selection", from the hotkey or the menu.
    @MainActor
    static func trigger() async {
        do {
            let selection = try await SelectionCapture.capture()
            log.debug("captured \(selection.text.count) chars from \(selection.appBundleID ?? "unknown")")
            PopoverController.show(selection: selection)
        } catch {
            log.error("capture failed: \(String(describing: error))")
            PopoverController.show(error: UserFacingError(error))
        }
    }
}
