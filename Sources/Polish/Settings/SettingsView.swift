import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppsSettings()
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 320)
    }
}

private struct GeneralSettings: View {
    @State private var hotkey = Hotkey.load()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @AppStorage(Preferences.summaryStyleKey) private var summaryStyle = SummaryStyle.bullets

    var body: some View {
        Form {
            LabeledContent("Shortcut") { HotkeyRecorder(hotkey: $hotkey) }

            Picker("Summarize as", selection: $summaryStyle) {
                ForEach(SummaryStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Section {
                Toggle("Launch Polish at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, setLoginItem)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// `SMAppService` is the store of record here, so on failure the toggle snaps back to it
    /// rather than to what the user just clicked.
    private func setLoginItem(_ previous: Bool, _ enabled: Bool) {
        do {
            loginItemError = nil
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = "Could not change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// The editable clipboard-fallback list. Bundle IDs, not names: that is what
/// `SelectionCapture.prefersClipboard` matches on.
private struct AppsSettings: View {
    @State private var apps = Preferences.fallbackApps()
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These apps do not expose their selection to macOS, so Polish copies it with ⌘C instead. Your clipboard is restored afterwards.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(apps, id: \.self, selection: $selection) { Text($0) }
                .border(.separator)

            HStack {
                Button("Add…", action: addFromChooser)
                Button("Remove") { remove(selection) }
                    .disabled(selection == nil)
                Spacer()
                Button("Reset") { save(Preferences.defaultFallbackApps) }
            }
        }
        .padding(20)
    }

    /// An open panel over /Applications rather than a text field: typing a bundle ID by hand is
    /// how you end up with a list entry that silently never matches.
    private func addFromChooser() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        save(apps + [bundleID])
    }

    private func remove(_ bundleID: String?) {
        guard let bundleID else { return }
        selection = nil
        save(apps.filter { $0 != bundleID })
    }

    private func save(_ newApps: [String]) {
        Preferences.setFallbackApps(newApps)
        apps = Preferences.fallbackApps()
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Polish").font(.title2).bold()
            Text(version).font(.caption).foregroundStyle(.secondary)
            Text("Rewrites the text you select, in any app, using Apple's on-device model. Nothing you write leaves your Mac.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show onboarding again") { OnboardingWindow.show() }
                .padding(.top, 4)
        }
        .padding(30)
    }
}
