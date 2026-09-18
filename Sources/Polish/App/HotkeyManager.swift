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

    /// How the combination reads in Settings, e.g. "⌃⌥P".
    var displayString: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + (Self.keyLabels[keyCode] ?? "Key \(keyCode)")
    }

    /// A recorder needs at least one non-shift modifier, or the shortcut swallows ordinary typing.
    var hasRequiredModifier: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }

    /// ponytail: ANSI/QWERTY labels only — enough for the recorder's read-out. Swap in
    /// `UCKeyTranslate` against the active layout if non-QWERTY users report wrong labels.
    private static let keyLabels: [UInt32: String] = {
        let ansi: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
            (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="), (kVK_ANSI_LeftBracket, "["),
            (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Semicolon, ";"),
            (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
            (kVK_ANSI_Slash, "/"), (kVK_ANSI_Grave, "`"),
            (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Delete, "⌫"),
            (kVK_Escape, "⎋"),
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"),
            (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"),
            (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]
        return Dictionary(uniqueKeysWithValues: ansi.map { (UInt32($0.0), $0.1) })
    }()
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

    /// Re-registers with a new combination, keeping the existing callback. Used by Settings.
    /// Returns false when the combination is already owned by another app.
    @discardableResult
    func update(hotkey: Hotkey) -> Bool {
        guard let onFire else { return false }
        return start(hotkey: hotkey, onFire: onFire)
    }

    /// Registers `hotkey`, replacing any previous registration. Safe to call again on change.
    /// Returns false when `RegisterEventHotKey` refused the combination.
    @discardableResult
    func start(hotkey: Hotkey = .load(), onFire: @escaping () -> Void) -> Bool {
        self.onFire = onFire
        unregister()

        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec, nil, &handlerRef)
        }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            // Another app owns this combination; Settings shows the failure and keeps the old value.
            Self.log.error("RegisterEventHotKey failed: \(status)")
            return false
        }
        return true
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
