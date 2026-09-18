import SwiftUI

/// Which backend runs the actions, and how to reach it when it is not the on-device one.
struct ModelSettings: View {
    @AppStorage(Preferences.providerKindKey) private var kind = InferenceProviderKind.apple
    @State private var config = Preferences.remoteConfig()
    @State private var apiKey = ""
    @State private var test: TestState = .idle

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
                    TextField("Model", text: $config.model, prompt: Text("gpt-4o-mini"))
                    TextField("Context size", value: $config.contextSize, format: .number)

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
        .onChange(of: apiKey) { saveKey() }
        .onAppear { apiKey = config.host.flatMap(APIKeyStore.load(forHost:)) ?? "" }
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
        Preferences.setRemoteConfig(config, .standard)
        test = .idle
    }

    private func saveKey() {
        guard let host = config.host else { return }
        try? APIKeyStore.save(apiKey, forHost: host)
        test = .idle
    }

    private func runTest() {
        // Replaced in Task 3 with a real five-token round trip against the endpoint.
        test = .failed("Not wired up yet")
    }
}
