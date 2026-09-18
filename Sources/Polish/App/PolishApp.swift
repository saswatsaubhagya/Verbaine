import AppKit
import SwiftUI

@main
struct PolishApp: App {
    var body: some Scene {
        MenuBarExtra("Polish", systemImage: "wand.and.sparkles") {
            // ponytail: placeholders until T1.1 wires the hotkey + capture pipeline
            Button("Improve selection") {}
                .disabled(true)
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
