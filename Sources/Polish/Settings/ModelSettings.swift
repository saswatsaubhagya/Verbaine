import SwiftUI

/// Which backend runs the actions, and how to reach it when it is not the on-device one.
struct ModelSettings: View {
    @AppStorage(Preferences.providerKindKey) private var kind = InferenceProviderKind.apple
    @State private var config = Preferences.remoteConfig()
    @State private var apiKey = ""
    @State private var test: TestState = .idle
    @State private var keySaveError: String?

    /// Base URLs only. Every one of these speaks the same wire format, so a preset is a text
    /// prefill and nothing more — there is no per-provider code anywhere in the app.
    private static let presets: [(name: String, url: String)] = [
        ("OpenAI", "https://api.openai.com/v1"),
        ("Anthropic", "https://api.anthropic.com/v1"),
        ("OpenRouter", "https://openrouter.ai/api/v1"),
        ("Groq", "https://api.groq.com/openai/v1"),
        ("Ollama (local)", "http://localhost:11434/v1"),
        ("LM Studio (local)", "http://localhost:1234/v1"),
    ]

    enum TestState: Equatable {
        case idle, running, passed
        case failed(String)
    }

    var body: some View {
        Form {
            Picker("Run actions with", selection: $kind) {
                ForEach(InferenceProviderKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)

            if kind == .remote {
                Section {
                    Picker("Preset", selection: presetBinding) {
                        Text("Choose…").tag("")
                        ForEach(Self.presets, id: \.url) { Text($0.name).tag($0.url) }
                    }
                    TextField("Base URL", text: $config.baseURL, prompt: Text("https://api.openai.com/v1"))
                    SecureField("API key", text: $apiKey)
                    if let keySaveError {
                        Text(keySaveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    TextField("Model", text: $config.model, prompt: Text("gpt-4o-mini"))
                    TextField("Context size", value: $config.contextSize, format: .number)
                    Text("In tokens, at least \(TokenBudget.minimumViableContextSize). "
                        + "A 128k window is 128000, not 128.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Test connection") { runTest() }
                            .disabled(!config.isComplete || test == .running)
                        testLabel
                    }
                } footer: {
                    Text("With a custom endpoint, the text you select is sent to that endpoint over the network. The on-device model never sends anything off this Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: config) { save() }
        .onChange(of: config.host) { _, newHost in reloadKey(forHost: newHost) }
        .onChange(of: apiKey) { saveKey() }
        .onAppear { reloadKey(forHost: config.host) }
    }

    private var presetBinding: Binding<String> {
        Binding(get: { "" }, set: { if !$0.isEmpty { config.baseURL = $0 } })
    }

    @ViewBuilder private var testLabel: some View {
        switch test {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .passed: Label("Reached it", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .failed(let message): Label(message, systemImage: "xmark.circle").foregroundStyle(.red)
        }
    }

    private func save() {
        // Floored here as well as in `Preferences`, so the field shows the value that was
        // actually stored rather than the unusable one that was typed.
        config.contextSize = max(TokenBudget.minimumViableContextSize, config.contextSize)
        Preferences.setRemoteConfig(config, .standard)
        test = .idle
    }

    /// What the API-key field should show right after the endpoint's host changes: the new
    /// host's own stored key, or empty when it has none. A pure lookup — factored out so the
    /// host-scoping invariant (a key never follows the field to a different host) can be tested
    /// without driving SwiftUI state.
    static func apiKeyOnHostChange(to host: String?) -> String {
        host.flatMap(APIKeyStore.load(forHost:)) ?? ""
    }

    /// Reloads `apiKey` for `host` synchronously, so the field can never carry the previous
    /// host's key into a save under this one — the reload runs off `config.host` changing, before
    /// the user's next keystroke can trigger `saveKey()`.
    private func reloadKey(forHost host: String?) {
        apiKey = Self.apiKeyOnHostChange(to: host)
        keySaveError = nil
    }

    private func saveKey() {
        guard let host = config.host else { return }
        do {
            try APIKeyStore.save(apiKey, forHost: host)
            keySaveError = nil
        } catch {
            keySaveError = Self.keySaveErrorMessage(for: error)
        }
        test = .idle
    }

    /// Maps a Keychain failure to the field's error line. The status code is safe to show; the
    /// key itself never is, and never reaches this string.
    static func keySaveErrorMessage(for error: any Error) -> String? {
        guard case let APIKeyStore.StoreError.keychain(status) = error else { return nil }
        return "Could not save the key (Keychain status \(status))."
    }

    private func runTest() {
        test = .running
        let config = self.config
        let key = self.apiKey
        Task {
            let provider = OpenAICompatibleProvider(config: config, apiKey: key)
            do {
                // Five tokens out and a one-word answer back: enough to prove the URL, the key and
                // the model name are all right, cheap enough to press repeatedly.
                _ = try await provider.respond(instructions: "Reply with the word OK.", prompt: "Ping")
                test = .passed
            } catch {
                test = .failed(UserFacingError(error).message)
            }
        }
    }
}
