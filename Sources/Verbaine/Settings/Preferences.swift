import Carbon.HIToolbox
import Foundation

/// The shape `Summarize` should return. Raw values persist in `UserDefaults`.
enum SummaryStyle: String, CaseIterable, Sendable, Identifiable {
    case bullets, paragraph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bullets: "Bullet points"
        case .paragraph: "Paragraph"
        }
    }
}

/// Everything the Settings window writes and the rest of the app reads.
///
/// Plain `UserDefaults` accessors rather than an observable store: only two values live here, and
/// SwiftUI reads both through `@AppStorage`/`@State` in `SettingsView`.
/// The hotkey has its own pair of keys in `Hotkey`; launch-at-login is stored by `SMAppService`.
enum Preferences {
    // MARK: Summary style

    static let summaryStyleKey = "summary.style"

    static func summaryStyle(_ defaults: UserDefaults = .standard) -> SummaryStyle {
        defaults.string(forKey: summaryStyleKey).flatMap(SummaryStyle.init(rawValue:)) ?? .bullets
    }

    // MARK: Clipboard-fallback apps

    static let fallbackAppsKey = "capture.fallbackBundleIDs"

    /// Apps known not to implement `kAXSelectedTextAttribute`, so only ⌘C gets their selection.
    /// The starting list; the Apps tab edits the stored copy.
    static let defaultFallbackApps: [String] = [
        "com.tinyspeck.slackmacgap",   // Slack
        "com.hnc.Discord",             // Discord
        "com.microsoft.VSCode",        // VS Code
        "com.google.Chrome",
        "company.thebrowser.Browser",  // Arc
        "com.figma.Desktop",
    ]

    /// An empty stored list is a real choice (the user removed every app), so only a missing key
    /// falls back to the defaults.
    static func fallbackApps(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: fallbackAppsKey) ?? defaultFallbackApps
    }

    /// Trims, drops blanks and de-duplicates, because the Apps tab is free text.
    static func setFallbackApps(_ apps: [String], _ defaults: UserDefaults = .standard) {
        var seen = Set<String>()
        let cleaned = apps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        defaults.set(cleaned, forKey: fallbackAppsKey)
    }

    // MARK: Per-app default tone

    static let defaultTonesKey = "tone.appDefaults"

    /// Bundle id → the tone `Change tone` should offer first in that app.
    static let builtInDefaultTones: [String: Tone] = [
        "com.tinyspeck.slackmacgap": .friendly,      // Slack
        "com.hnc.Discord": .friendly,
        "com.apple.mail": .professional,
        "com.microsoft.Outlook": .professional,
        "com.atlassian.jira": .direct,
        "com.linear": .direct,
    ]

    /// An empty stored map is a real choice (the user cleared it), so only a missing key falls
    /// back to the built-ins — same rule as the fallback-app list above.
    static func defaultTones(_ defaults: UserDefaults = .standard) -> [String: Tone] {
        guard let stored = defaults.dictionary(forKey: defaultTonesKey) as? [String: String] else {
            return builtInDefaultTones
        }
        // ponytail: unknown raw values are dropped rather than migrated — an older/newer build's
        // tone name just means "no preset for this app".
        return stored.compactMapValues(Tone.init(rawValue:))
    }

    static func setDefaultTones(_ tones: [String: Tone], _ defaults: UserDefaults = .standard) {
        defaults.set(tones.mapValues(\.rawValue), forKey: defaultTonesKey)
    }

    /// The tone to preselect for the app the selection came from.
    static func defaultTone(forBundleID bundleID: String?, _ defaults: UserDefaults = .standard) -> Tone {
        bundleID.flatMap { defaultTones(defaults)[$0] } ?? .professional
    }

    /// `Tone.allCases` with that app's preset first, so the popover's menu can preselect it by
    /// ordering alone — no selection state to thread through the UI.
    static func tones(forBundleID bundleID: String?, _ defaults: UserDefaults = .standard) -> [Tone] {
        let preferred = defaultTone(forBundleID: bundleID, defaults)
        return [preferred] + Tone.allCases.filter { $0 != preferred }
    }
}

// MARK: Custom actions

extension Preferences {
    static let customActionsKey = "actions.custom"

    /// JSON rather than a plist dictionary: `CustomAction` is `Codable` and nests an optional
    /// `Hotkey`, which `UserDefaults` cannot store on its own.
    static func customActions(_ defaults: UserDefaults = .standard) -> [CustomAction] {
        guard let data = defaults.data(forKey: customActionsKey),
              let actions = try? JSONDecoder().decode([CustomAction].self, from: data)
        else { return [] }
        return actions
    }

    static func setCustomActions(_ actions: [CustomAction], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        defaults.set(data, forKey: customActionsKey)
    }
}

// MARK: Per-action hotkeys

extension Preferences {
    static let actionHotkeysKey = "actions.hotkeys"

    /// Built-in actions that ship with a shortcut. Fix grammar is the PRD's example
    /// ("⌃⌥G = fix grammar and replace immediately"), so it is bound out of the box.
    static let builtInActionHotkeys: [String: Hotkey] = [
        Action.fixGrammar.id: Hotkey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey)),
    ]

    /// `Action.id` → the shortcut that runs it silently. Custom actions keep theirs in
    /// `CustomAction.hotkey`; this map is for the built-in grid only.
    ///
    /// An empty stored map is a real choice (the user cleared every shortcut), so only a missing
    /// key falls back to the built-ins — same rule as the fallback-app and tone maps above.
    static func actionHotkeys(_ defaults: UserDefaults = .standard) -> [String: Hotkey] {
        guard let data = defaults.data(forKey: actionHotkeysKey),
              let stored = try? JSONDecoder().decode([String: Hotkey].self, from: data)
        else { return builtInActionHotkeys }
        return stored
    }

    static func setActionHotkeys(_ hotkeys: [String: Hotkey], _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(hotkeys) else { return }
        defaults.set(data, forKey: actionHotkeysKey)
    }

    /// Every action with a shortcut: the built-in grid first, then the user's own.
    static func hotkeyedActions(_ defaults: UserDefaults = .standard) -> [(action: Action, hotkey: Hotkey)] {
        let builtIn = actionHotkeys(defaults).compactMap { id, hotkey in
            Action(id: id).map { (action: $0, hotkey: hotkey) }
        }
        let custom = customActions(defaults).compactMap { action in
            action.hotkey.map { (action: Action.custom(action), hotkey: $0) }
        }
        return builtIn.sorted { $0.action.id < $1.action.id } + custom
    }
}

// MARK: Inference provider

extension Preferences {
    static let providerKindKey = "model.provider"
    static let remoteBaseURLKey = "model.remote.baseURL"
    static let remoteModelKey = "model.remote.model"
    static let remoteContextSizeKey = "model.remote.contextSize"

    /// Unknown raw values fall back to the on-device model: the safe direction, because it is the
    /// one that cannot send anything off the Mac.
    static func providerKind(_ defaults: UserDefaults = .standard) -> InferenceProviderKind {
        defaults.string(forKey: providerKindKey).flatMap(InferenceProviderKind.init(rawValue:)) ?? .apple
    }

    static func setProviderKind(_ kind: InferenceProviderKind, _ defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: providerKindKey)
    }

    static func remoteConfig(_ defaults: UserDefaults = .standard) -> RemoteConfig {
        RemoteConfig(
            baseURL: defaults.string(forKey: remoteBaseURLKey) ?? "",
            model: defaults.string(forKey: remoteModelKey) ?? "",
            contextSize: (defaults.object(forKey: remoteContextSizeKey) as? Int)
                .map { max(TokenBudget.minimumViableContextSize, $0) }
                ?? RemoteConfig.defaultContextSize
        )
    }

    static func setRemoteConfig(_ config: RemoteConfig, _ defaults: UserDefaults = .standard) {
        defaults.set(config.baseURL.trimmingCharacters(in: .whitespaces), forKey: remoteBaseURLKey)
        defaults.set(config.model.trimmingCharacters(in: .whitespaces), forKey: remoteModelKey)
        // Floored, not just made positive: a window under this leaves the chunkers no room at
        // all and every action comes back empty. See `TokenBudget.minimumViableContextSize`.
        defaults.set(
            max(TokenBudget.minimumViableContextSize, config.contextSize),
            forKey: remoteContextSizeKey
        )
    }
}
