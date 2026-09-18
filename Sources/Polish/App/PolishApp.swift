import AppKit
import SwiftUI

@main
struct PolishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Polish", systemImage: "wand.and.sparkles") {
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
