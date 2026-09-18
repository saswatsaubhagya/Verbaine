import Carbon.HIToolbox
import os

/// The user's global shortcut, as Carbon wants it: a virtual key code plus Carbon modifier mask.
/// Carbon is still the only API that gets a key event when another app is frontmost without
/// asking for Input Monitoring on top of Accessibility, so `RegisterEventHotKey` it is.
struct Hotkey: Equatable, Sendable {
    var keyCode: UInt32
    /// `controlKey`, `optionKey`, `cmdKey`, `shiftKey` OR'd together.
    var modifiers: UInt32

    /// ⌃⌥P — free in macOS and in the apps Polish targets.
    static let standard = Hotkey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey))

    private static let keyCodeKey = "hotkey.keyCode"
    private static let modifiersKey = "hotkey.modifiers"

    /// Falls back to `.standard` unless both halves were stored; a half-written pair is not a hotkey.
    static func load(from defaults: UserDefaults = .standard) -> Hotkey {
        guard let keyCode = defaults.object(forKey: keyCodeKey) as? Int,
              let modifiers = defaults.object(forKey: modifiersKey) as? Int
        else { return .standard }
        return Hotkey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(modifiers), forKey: Self.modifiersKey)
    }
}

/// Registers one global hotkey and calls back on the main actor when it fires.
/// A singleton because the Carbon handler is a C function pointer with nowhere to carry `self`.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let log = Logger(subsystem: "com.saswat.polish", category: "Hotkey")
    private static let signature: OSType = 0x504C5348  // 'PLSH'

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onFire: (() -> Void)?

    private init() {}

    /// Registers `hotkey`, replacing any previous registration. Safe to call again on change (T1.8).
    func start(hotkey: Hotkey = .load(), onFire: @escaping () -> Void) {
        self.onFire = onFire
        unregister()

        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec, nil, &handlerRef)
        }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            // Another app owns this combination; the user picks a different one in Settings (T1.8).
            Self.log.error("RegisterEventHotKey failed: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    fileprivate func fire() {
        Self.log.debug("hotkey fired")
        onFire?()
    }
}

/// Carbon calls this on the main run loop, so the hop to `HotkeyManager` is isolation-safe.
private let hotkeyHandler: EventHandlerUPP = { _, _, _ in
    MainActor.assumeIsolated { HotkeyManager.shared.fire() }
    return noErr
}
