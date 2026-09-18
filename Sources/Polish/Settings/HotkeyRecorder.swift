import Carbon.HIToolbox
import SwiftUI

/// A button that shows the current shortcut and, while armed, swallows the next key press to
/// become the new one.
///
/// A local `NSEvent` monitor rather than an `NSViewRepresentable` first responder: the Settings
/// window is frontmost whenever this view is on screen, so a local monitor sees every key down
/// with a fraction of the code.
struct HotkeyRecorder: View {
    /// `nil` means "no shortcut" — a custom action may have none.
    @Binding var hotkey: Hotkey?
    /// What the second button does: restore `reset` (the app-wide shortcut) or clear the binding
    /// (a custom action's, which is optional).
    var reset: Hotkey? = .standard
    /// Tries the combination for real before it is kept. The app-wide shortcut re-registers here;
    /// a custom action's is registered in bulk when Settings saves the list.
    var register: (Hotkey) -> Bool = { HotkeyManager.shared.update(hotkey: $0) }
    /// Set when `RegisterEventHotKey` refused the combination the user pressed.
    @State private var conflict = false
    @State private var monitor: Any?

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(isRecording ? "Press keys…" : (hotkey?.displayString ?? "None")) {
                    isRecording ? stop() : start()
                }
                .frame(minWidth: 90)

                Button(reset == nil ? "Clear" : "Reset") {
                    stop()
                    conflict = false
                    if let reset { apply(reset) } else { hotkey = nil }
                }
                .disabled(hotkey == reset)
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
        guard register(candidate) else {
            conflict = true
            if let hotkey { _ = register(hotkey) }
            return
        }
        conflict = false
        if reset != nil { candidate.save() }
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
