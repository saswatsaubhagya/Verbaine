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
