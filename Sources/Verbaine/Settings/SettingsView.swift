import AppKit
import ServiceManagement
import SwiftUI

/// Settings, 640 × 430 and tabbed, as the board draws it (row 6): General, Actions, Apps, About.
///
/// The Model tab is not on the board — bring-your-own-endpoint (T3.6–T3.9) landed after it was
/// drawn — so it sits between Apps and About rather than displacing a board tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            CustomActionsSettings()
                .tabItem { Label("Actions", systemImage: "wand.and.stars") }
            AppsSettings()
                .tabItem { Label("Apps", systemImage: "app.badge") }
            ModelSettings()
                .tabItem { Label("Model", systemImage: "cpu") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: Tokens.Size.settings.width, height: Tokens.Size.settings.height)
    }
}

/// A settings row the board's way: a right-aligned label in a fixed gutter, control beside it.
private struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            Text(label)
                .font(Tokens.Face.body)
                .foregroundStyle(Tokens.Ink.secondary)
                .frame(width: 140, alignment: .trailing)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) { content }
            Spacer(minLength: 0)
        }
    }
}

private struct GeneralSettings: View {
    @State private var hotkey = Hotkey.load()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @AppStorage(Preferences.summaryStyleKey) private var summaryStyle = SummaryStyle.bullets

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            SettingRow(label: "Verbaine shortcut:") {
                HotkeyRecorder(hotkey: Binding(get: { hotkey }, set: { hotkey = $0 ?? .standard }))
            }

            SettingRow(label: "Startup:") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin, setLoginItem)
                if let loginItemError {
                    Text(loginItemError)
                        .font(Tokens.Face.footerMeta)
                        .foregroundStyle(Tokens.Palette.removed)
                }
            }

            SettingRow(label: "Summary style:") {
                Picker("", selection: $summaryStyle) {
                    ForEach(SummaryStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
                Text("Applies to Summarize and to long-text results.")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
            }

            Spacer()
        }
        .padding(Tokens.Space.window)
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
    @State private var tones = Preferences.defaultTones()
    @State private var toneSelection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Default tone per app").paneHeaderStyle()

            List(tones.keys.sorted(), id: \.self, selection: $toneSelection) { bundleID in
                HStack {
                    Text(bundleID).font(Tokens.Face.body)
                    Spacer()
                    Picker("", selection: toneBinding(bundleID)) {
                        ForEach(Tone.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            .border(Tokens.Palette.hairline)
            .frame(height: 96)

            HStack {
                Button("Add…", action: addToneFromChooser)
                Button("Remove") { removeTone(toneSelection) }
                    .disabled(toneSelection == nil)
                Spacer()
                Button("Reset") { saveTones(Preferences.builtInDefaultTones) }
            }

            Text("Using clipboard fallback").paneHeaderStyle()

            List(apps, id: \.self, selection: $selection) { Text($0).font(Tokens.Face.body) }
                .border(Tokens.Palette.hairline)
                .frame(height: 96)

            HStack {
                Button("Add…", action: addFromChooser)
                Button("Remove") { remove(selection) }
                    .disabled(selection == nil)
                Spacer()
                Button("Reset") { save(Preferences.defaultFallbackApps) }
            }

            Text("These apps don't expose an editable text field to Accessibility. Verbaine copies the selection with ⌘C and puts the result on the clipboard; your clipboard is restored afterwards.")
                .font(Tokens.Face.footerMeta)
                .foregroundStyle(Tokens.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.window)
    }

    /// Writes straight through on every change — there is no Save button in this window.
    private func toneBinding(_ bundleID: String) -> Binding<Tone> {
        Binding(
            get: { tones[bundleID] ?? .professional },
            set: { saveTones(tones.merging([bundleID: $0]) { _, new in new }) }
        )
    }

    private func addToneFromChooser() {
        // ponytail: same chooser as above, deliberately duplicated rather than factored out —
        // two call sites, and the factored version needs a closure parameter to be worth it.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        saveTones(tones.merging([bundleID: .professional]) { old, _ in old })
    }

    private func removeTone(_ bundleID: String?) {
        guard let bundleID else { return }
        toneSelection = nil
        saveTones(tones.filter { $0.key != bundleID })
    }

    private func saveTones(_ newTones: [String: Tone]) {
        Preferences.setDefaultTones(newTones)
        tones = Preferences.defaultTones()
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
        VStack(spacing: Tokens.Space.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Verbaine")
                .font(Tokens.Face.headline)
                .foregroundStyle(Tokens.Ink.primary)
            Text(version)
                .font(Tokens.Face.footerMeta)
                .foregroundStyle(Tokens.Ink.tertiary)
                .monospacedDigit()
            Text("macOS 26 or later · Apple silicon")
                .font(Tokens.Face.footerMeta)
                .foregroundStyle(Tokens.Ink.tertiary)
            Text("Verbaine rewrites selected text using Apple's Foundation Models, built into macOS. Every rewrite runs on this Mac. No account, no servers, no telemetry.")
                .font(Tokens.Face.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Tokens.Space.windowWide)
            Button("Reset onboarding") { OnboardingWindow.show() }
                .padding(.top, Tokens.Space.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Tokens.Space.window)
    }
}

/// Settings → Actions: every action in one table — the built-ins with the button they finish on
/// and their shortcut, then the user's own actions, which are editable (T3.1).
private struct CustomActionsSettings: View {
    @State private var actions = Preferences.customActions()
    @State private var selection: CustomAction.ID?
    @State private var editing: CustomAction.ID?
    @State private var error: String?
    @State private var hotkeys = Preferences.actionHotkeys()

    private var selected: Binding<CustomAction>? {
        guard let index = actions.firstIndex(where: { $0.id == editing }) else { return nil }
        return Binding(get: { actions[index] }, set: { edited in
            var updated = actions
            updated[index] = edited
            save(updated)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(Action.grid) { action in
                        row(
                            title: action.title,
                            defaultButton: action.defaultButton.title,
                            hotkey: builtInBinding(for: action)
                        )
                    }

                    Text("Custom").paneHeaderStyle().padding(.top, Tokens.Space.s)

                    ForEach(actions) { action in
                        row(
                            title: action.name.isEmpty ? "Untitled" : action.name,
                            defaultButton: action.defaultButton.title,
                            hotkey: customBinding(for: action),
                            isSelected: selection == action.id
                        )
                        .contentShape(.rect)
                        .onTapGesture { selection = action.id }
                        .onTapGesture(count: 2) { editing = action.id }
                    }
                }
            }

            HStack {
                Button("Add", action: add)
                Button("Edit") { editing = selection }
                    .disabled(selection == nil)
                Button("Remove") { remove(selection) }
                    .disabled(selection == nil)
                Spacer()
                Text("A shortcut runs its action straight away and replaces the selection — no popover unless something goes wrong.")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        }
        .padding(Tokens.Space.window)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let selected { editor(selected) }
        }
    }

    private var header: some View {
        HStack {
            Text("Action").paneHeaderStyle().frame(maxWidth: .infinity, alignment: .leading)
            Text("Default button").paneHeaderStyle().frame(width: 120, alignment: .leading)
            Text("Hotkey").paneHeaderStyle().frame(width: 150, alignment: .leading)
        }
    }

    private func row(
        title: String,
        defaultButton: String,
        hotkey: Binding<Hotkey?>,
        isSelected: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(Tokens.Face.body)
                .foregroundStyle(Tokens.Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(defaultButton)
                .font(Tokens.Face.body)
                .foregroundStyle(Tokens.Ink.secondary)
                .frame(width: 120, alignment: .leading)
            HotkeyRecorder(hotkey: hotkey, reset: nil, register: { _ in true })
                .frame(width: 150, alignment: .leading)
        }
        .padding(.horizontal, Tokens.Space.xs)
        .padding(.vertical, Tokens.Space.xxs)
        .background(
            isSelected ? Tokens.Palette.accent.opacity(0.13) : .clear,
            in: .rect(cornerRadius: Tokens.Radius.menuItem)
        )
    }

    /// The edit sheet from the board: name, instruction, default button, hotkey, Cancel / Save.
    @ViewBuilder
    private func editor(_ action: Binding<CustomAction>) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text("Edit action")
                .font(Tokens.Face.windowTitle)
                .foregroundStyle(Tokens.Ink.primary)

            SettingRow(label: "Name:") {
                TextField("", text: action.name).frame(width: 260)
            }

            SettingRow(label: "Instruction:") {
                TextEditor(text: action.instruction)
                    .font(Tokens.Face.body)
                    .frame(width: 320, height: 80)
                    .border(Tokens.Palette.hairline)
                Text("What the model should do with the selected text, e.g. “Rewrite this as a release note.” Up to \(CustomAction.maxInstructionTokens) tokens.")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingRow(label: "Default button:") {
                Picker("", selection: action.defaultButton) {
                    ForEach(CustomAction.DefaultButton.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            SettingRow(label: "Hotkey:") {
                HotkeyRecorder(hotkey: action.hotkey, reset: nil, register: { _ in true })
            }

            if let error {
                Text(error)
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Palette.removed)
            }

            HStack {
                Spacer()
                Button("Done") { editing = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.window)
        .frame(width: 520)
    }

    private func builtInBinding(for action: Action) -> Binding<Hotkey?> {
        Binding(
            get: { hotkeys[action.id] },
            set: { hotkey in
                hotkeys[action.id] = hotkey
                Preferences.setActionHotkeys(hotkeys)
                AppDelegate.registerActionHotkeys()
            }
        )
    }

    private func customBinding(for action: CustomAction) -> Binding<Hotkey?> {
        Binding(
            get: { action.hotkey },
            set: { hotkey in
                guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
                var updated = actions
                updated[index].hotkey = hotkey
                save(updated)
            }
        )
    }

    private func add() {
        var updated = actions
        let new = CustomAction(name: "New action", instruction: "")
        updated.append(new)
        save(updated)
        selection = new.id
        editing = new.id
    }

    private func remove(_ id: CustomAction.ID?) {
        guard let id else { return }
        selection = nil
        save(actions.filter { $0.id != id })
    }

    /// Saves first, then validates the edited action and reports what is wrong with it — typing a
    /// name one character at a time would otherwise be a stream of "give the action a name".
    private func save(_ updated: [CustomAction]) {
        Preferences.setCustomActions(updated)
        actions = Preferences.customActions()
        AppDelegate.registerActionHotkeys()

        guard let edited = updated.first(where: { $0.id == editing }) else {
            error = nil
            return
        }
        Task {
            let tokens = await CustomAction.tokenCount(of: edited.instruction)
            error = CustomAction.validationError(name: edited.name, instruction: edited.instruction, tokens: tokens)
        }
    }
}
