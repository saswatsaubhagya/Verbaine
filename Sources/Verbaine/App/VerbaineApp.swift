import AppKit
import SwiftUI

@main
struct VerbaineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Drives the menu-bar symbol. Reading the preference directly rather than
    /// `Inference.current.isRemote` keeps this a value SwiftUI can observe.
    @AppStorage(Preferences.providerKindKey) private var providerKind = InferenceProviderKind.apple

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            // The board's monochrome template mark (row 7); a cloud when the user's own endpoint
            // is doing the writing, so the menu bar always says where the text is going.
            if providerKind == .remote {
                Image(systemName: "cloud")
            } else {
                Image("MenuBarIcon")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// The menu-bar dropdown from board row 3: every action with its shortcut, then Settings and
/// Quit. Clipboard history is T4.6 and deliberately absent in v1.
private struct MenuBarContent: View {
    private let hotkeys = Preferences.actionHotkeys()
    private let customActions = Preferences.customActions()

    var body: some View {
        ForEach(Action.grid) { action in
            button(for: action)
        }

        if !customActions.isEmpty {
            Divider()
            ForEach(customActions.map(Action.custom)) { action in
                button(for: action)
            }
        }

        Divider()
#if DEBUG
        DebugMenu()
        Divider()
#endif
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Verbaine") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Firing an action from the menu goes through the popover; the hotkey itself is what runs
    /// silently (T3.2), so the shortcut here is only a reminder of what that key does.
    // ponytail: the board draws the shortcut in a right-aligned column, which needs a hand-built
    // NSMenu. A help tag carries the same information for the price of one line.
    private func button(for action: Action) -> some View {
        Button(action.title) { Task { await AppDelegate.trigger(action: action) } }
            .help(hint(for: action))
    }

    private func hint(for action: Action) -> String {
        guard let hotkey = hotkeys[action.id] ?? action.customHotkey else { return action.title }
        return "\(action.title) — \(hotkey.displayString)"
    }
}

private extension Action {
    /// A custom action stores its own hotkey rather than living in `Preferences.actionHotkeys`.
    var customHotkey: Hotkey? {
        if case .custom(let action) = self { return action.hotkey }
        return nil
    }
}
