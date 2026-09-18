import Carbon.HIToolbox
import CoreGraphics
import os

/// Types a chord into the system event stream on the user's behalf.
///
/// Capture presses ⌘C (T0.4) and write-back presses ⌘V (T0.5); both reach the frontmost app as
/// if the user had typed them, which is the only way to get text in and out of Electron apps
/// while leaving their own undo stack intact. Needs the same Accessibility trust as reading.
enum SyntheticKeystroke {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "SyntheticKeystroke")

    static func postCommandC() { post(key: CGKeyCode(kVK_ANSI_C)) }
    static func postCommandV() { post(key: CGKeyCode(kVK_ANSI_V)) }
    static func postCommandZ() { post(key: CGKeyCode(kVK_ANSI_Z)) }

    private static func post(key: CGKeyCode) {
        // A private source keeps our synthetic modifiers out of the user's real keyboard state,
        // so a physically held key does not get mixed into the chord.
        let source = CGEventSource(stateID: .privateState)

        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else {
                log.error("could not create key event for \(key)")
                return
            }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
