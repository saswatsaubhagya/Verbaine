import AppKit
import SwiftUI

@main
struct PolishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Drives the menu-bar symbol. Reading the preference directly rather than
    /// `Inference.current.isRemote` keeps this a value SwiftUI can observe.
    @AppStorage(Preferences.providerKindKey) private var providerKind = InferenceProviderKind.apple

    var body: some Scene {
        MenuBarExtra("Polish", systemImage: providerKind == .remote ? "wand.and.sparkles.inverse" : "wand.and.sparkles") {
            Button("Improve selection") { Task { await AppDelegate.trigger() } }
            Divider()
#if DEBUG
            DebugMenu()
            Divider()
#endif
            SettingsLink { Text("Settings…") }
            Button("Quit Polish") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView()
        }
    }
}
