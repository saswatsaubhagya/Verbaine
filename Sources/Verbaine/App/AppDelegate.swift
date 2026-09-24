import AppKit
import os

/// Owns the app-lifetime wiring the SwiftUI `Scene` has no place for: the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "in.saswatsaubhagya.verbaine", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.start { Task { await AppDelegate.trigger() } }
        AppDelegate.registerActionHotkeys()
        NSApp.servicesProvider = ServicesProvider.shared
        // ponytail: the services cache only picks up a debug build's NSServices after a nudge;
        // harmless in a released build, which the installer refreshes anyway.
        NSUpdateDynamicServices()
        OnboardingWindow.showIfNeeded()
    }

    /// Registers a global shortcut for every action that has one — the built-in grid (T3.2) and
    /// the user's own (T3.1). Called again by Settings whenever either list changes.
    @MainActor
    static func registerActionHotkeys() {
        let entries = Preferences.hotkeyedActions().map { entry in
            (hotkey: entry.hotkey, onFire: { _ = Task { await AppDelegate.trigger(action: entry.action, silent: true) } })
        }
        HotkeyManager.shared.setExtraHotkeys(entries)
    }

    /// The single entry point for "user asked to polish the selection", from the hotkey or the
    /// menu. `action` runs straight away; `silent` also replaces without a popover, which is what
    /// a per-action shortcut does.
    @MainActor
    static func trigger(action: Action? = nil, silent: Bool = false) async {
        do {
            let selection = try await SelectionCapture.capture()
            log.debug("captured \(selection.text.count) chars from \(selection.appBundleID ?? "unknown")")
            if silent, let action {
                await PopoverController.runSilently(selection: selection, action: action)
            } else {
                PopoverController.show(selection: selection, run: action)
            }
        } catch {
            log.error("capture failed: \(String(describing: error))")
            PopoverController.show(error: UserFacingError(error))
        }
    }
}
