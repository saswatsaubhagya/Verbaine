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
}
