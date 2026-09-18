import AppKit
import os

/// Owns the app-lifetime wiring the SwiftUI `Scene` has no place for: the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.shared.start { Task { await AppDelegate.trigger() } }
        AppDelegate.registerCustomActionHotkeys()
        NSApp.servicesProvider = ServicesProvider.shared
        // ponytail: the services cache only picks up a debug build's NSServices after a nudge;
        // harmless in a released build, which the installer refreshes anyway.
        NSUpdateDynamicServices()
        OnboardingWindow.showIfNeeded()
    }

    /// Registers a global shortcut for every custom action that has one (T3.1). Called again by
    /// Settings whenever the list changes.
    @MainActor
    static func registerCustomActionHotkeys() {
        let entries: [(hotkey: Hotkey, onFire: () -> Void)] = Preferences.customActions().compactMap { action in
            guard let hotkey = action.hotkey else { return nil }
            return (hotkey: hotkey, onFire: { Task { await AppDelegate.trigger(action: .custom(action)) } })
        }
        HotkeyManager.shared.setExtraHotkeys(entries)
    }

    /// The single entry point for "user asked to polish the selection", from the hotkey or the
    /// menu. `action` runs straight away — that is how a custom action's shortcut works.
    @MainActor
    static func trigger(action: Action? = nil) async {
        do {
            let selection = try await SelectionCapture.capture()
            log.debug("captured \(selection.text.count) chars from \(selection.appBundleID ?? "unknown")")
            PopoverController.show(selection: selection, run: action)
        } catch {
            log.error("capture failed: \(String(describing: error))")
            PopoverController.show(error: UserFacingError(error))
        }
    }
}
