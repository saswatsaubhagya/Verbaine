import Carbon.HIToolbox
import SwiftUI

/// A button that shows the current shortcut and, while armed, swallows the next key press to
/// become the new one.
///
/// A local `NSEvent` monitor rather than an `NSViewRepresentable` first responder: the Settings
/// window is frontmost whenever this view is on screen, so a local monitor sees every key down
/// with a fraction of the code.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    /// Set when `RegisterEventHotKey` refused the combination the user pressed.
    @State private var conflict = false
    @State private var monitor: Any?

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(isRecording ? "Press keys…" : hotkey.displayString) {
                    isRecording ? stop() : start()
                }
                .frame(minWidth: 90)

                Button("Reset") {
                    stop()
                    apply(.standard)
                }
                .disabled(hotkey == .standard)
            }

            if isRecording {
                Text("Hold ⌃, ⌥ or ⌘ and press a key. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if conflict {
                Text("Another app already uses that shortcut.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        conflict = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil  // never let the recorded key reach the window
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        stop()
        guard Int(event.keyCode) != kVK_Escape else { return }
        let candidate = Hotkey(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
        // Without ⌃/⌥/⌘ the shortcut would fire on ordinary typing in every app.
        guard candidate.hasRequiredModifier else {
            conflict = false
            return
        }
        apply(candidate)
    }

    /// Re-registers first: an unavailable combination must not be saved, or the app relaunches
    /// with a hotkey that never fires.
    private func apply(_ candidate: Hotkey) {
        guard HotkeyManager.shared.update(hotkey: candidate) else {
            conflict = true
            HotkeyManager.shared.update(hotkey: hotkey)
            return
        }
        conflict = false
        candidate.save()
        hotkey = candidate
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }
}
