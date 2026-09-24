# Bring-your-own-key remote provider — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user point Verbaine at their own OpenAI-compatible endpoint with their own API key, while Apple's on-device model stays the default and the UI always says when text is leaving the Mac.

**Architecture:** `ParagraphRewriter.swift` and `TokenBudget.swift` already declare `TextGenerating` and `TokenCounting`, and `ModelService` is their only conformer. Task 1 composes them into one `InferenceProvider` protocol and adds an `Inference.current` resolver that every caller goes through; Tasks 2–3 add a second conformer that speaks the OpenAI `/chat/completions` wire format over `URLSession`; Task 4 makes the remote case visible and legal.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI + AppKit, FoundationModels, Foundation `URLSession`, Security.framework (Keychain), swift-testing (`import Testing`). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-byok-remote-provider-design.md`

## Global Constraints

- Swift 6 strict concurrency. Every type crossing a boundary is `Sendable`.
- No third-party dependencies. Security.framework and Foundation only.
- Never hard-code 4096. Read `contextSize` from the provider.
- All prompts stay in `Sources/Verbaine/Model/Prompts.swift`, one static string per action, each ≤ 120 tokens. This feature adds no prompts.
- One fresh session per action, no history carried between calls — for remote this means one `URLRequest` per action, with `messages` rebuilt from scratch every time.
- Never truncate silently. Every failure maps to a `UserFacingError` sentence plus one remedy.
- The API key lives only in the Keychain. Never in `UserDefaults`, never in a log line, never in an error message.
- Target folders are file-system synchronized: a new file under `Sources/Verbaine/` joins the app target with no `.xcodeproj` edit. Swift file basenames must stay unique across the target.
- Build and test commands, both must pass before any task is done:

```sh
xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' build
xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test
```

- Tests use swift-testing (`@Test`, `#expect`), not XCTest. No test may touch the network or the real `UserDefaults.standard`.

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `Sources/Verbaine/Model/InferenceProvider.swift` | The one protocol every provider conforms to; `TextGenerating` and `TokenCounting` move here | 1 |
| `Sources/Verbaine/Model/Inference.swift` | `Inference.current` — resolves the active provider from `Preferences` on every call | 1 |
| `Sources/Verbaine/Model/Remote/RemoteConfig.swift` | Base URL, model name, declared context size; `Preferences` storage | 2 |
| `Sources/Verbaine/Model/Remote/APIKeyStore.swift` | Keychain save / load / delete, keyed by endpoint host | 2 |
| `Sources/Verbaine/Settings/ModelSettings.swift` | The Settings "Model" tab, including Test connection | 2 |
| `Sources/Verbaine/Model/Remote/RemoteError.swift` | HTTP status and `URLError` → a typed error | 3 |
| `Sources/Verbaine/Model/Remote/SSEStream.swift` | SSE lines → cumulative content snapshots | 3 |
| `Sources/Verbaine/Model/Remote/OpenAICompatibleProvider.swift` | The `InferenceProvider` that talks to the endpoint | 3 |
| `Sources/Verbaine/App/VerbaineApp.swift` | Menu-bar symbol swaps when remote is active | 4 |
| `Sources/Verbaine/UI/PopoverView.swift` | `via <model> · cloud` line under the action grid | 4 |

---

### Task 1: `InferenceProvider` protocol and the `Inference` resolver

Pure refactor. No behaviour changes, no new capability. It is its own task so that the 115 existing tests prove the seam is neutral before anything remote exists.

**Files:**
- Create: `Sources/Verbaine/Model/InferenceProvider.swift`
- Create: `Sources/Verbaine/Model/Inference.swift`
- Modify: `Sources/Verbaine/Model/ParagraphRewriter.swift` (delete the `TextGenerating` declaration and the `ModelService` conformance, change the convenience `init`)
- Modify: `Sources/Verbaine/Model/TokenBudget.swift` (delete the `TokenCounting` declaration and the `ModelService` conformance, change the convenience `init`)
- Modify: `Sources/Verbaine/Model/TextChunker.swift`, `Sources/Verbaine/Model/MapReduceSummarizer.swift` (convenience `init` signature)
- Modify: `Sources/Verbaine/Model/ModelService.swift` (add the two new members)
- Modify: `Sources/Verbaine/UI/PopoverModel.swift`, `Sources/Verbaine/Model/CustomAction.swift`, `Sources/Verbaine/App/ServicesProvider.swift`, `Sources/Verbaine/App/DebugMenu.swift` (`ModelService.shared` → `Inference.current`)
- Test: `Tests/VerbaineTests/InferenceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `protocol InferenceProvider: TextGenerating, TokenCounting, Sendable` with `var availability: ModelAvailability`, `var contextSize: Int`, `var isRemote: Bool`, `var displayName: String`, `func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error>`. `enum Inference { static var current: any InferenceProvider }`. Every later task's provider conforms to this exact protocol.

- [ ] **Step 1: Write the failing test**

Create `Tests/VerbaineTests/InferenceTests.swift`:

```swift
import Testing
@testable import Verbaine

@Test("the on-device model is the default provider and is not remote")
func defaultProviderIsApple() {
    let provider = Inference.current
    #expect(provider.isRemote == false)
    #expect(provider.displayName == "Apple on-device")
}

@Test("the on-device provider reports the model's own context window, never an assumed 4096")
func appleProviderReportsContextSize() {
    #expect(Inference.current.contextSize > 0)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: FAIL to compile — "cannot find 'Inference' in scope".

- [ ] **Step 3: Create the protocol file**

Create `Sources/Verbaine/Model/InferenceProvider.swift`. The two protocol declarations move here verbatim from `ParagraphRewriter.swift` and `TokenBudget.swift`, so their doc comments come along:

```swift
import Foundation

/// Anything that can answer one prompt. `ModelService` is the on-device one; tests stub it so they
/// run on machines without Apple Intelligence.
protocol TextGenerating: Sendable {
    func respond(instructions: String, prompt: String) async throws -> String
}

/// Anything that can measure tokens. `ModelService` measures exactly, via the framework's own
/// tokenizer; a remote provider can only estimate.
protocol TokenCounting: Sendable {
    func tokenCount(for text: String) async throws -> Int
}

/// One whole inference backend: the on-device model, or a user-configured remote endpoint.
///
/// The two protocols above stay separate because `TokenBudget` and `ParagraphRewriter` are tested
/// against tiny stubs that have no business implementing a whole backend.
protocol InferenceProvider: TextGenerating, TokenCounting, Sendable {
    /// Whether this provider will answer right now. Cheap and safe to poll from the UI.
    var availability: ModelAvailability { get }
    /// The full context window in tokens.
    var contextSize: Int { get }
    /// True when using this provider sends the user's text off the Mac. Drives the menu-bar symbol
    /// and the popover badge — the user must never be unsure which one is running.
    var isRemote: Bool { get }
    /// What the popover calls this provider, e.g. "Apple on-device" or "gpt-4o-mini".
    var displayName: String { get }

    func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error>
}
```

- [ ] **Step 4: Delete the two moved declarations**

In `Sources/Verbaine/Model/ParagraphRewriter.swift`, delete the `protocol TextGenerating` block and the line `extension ModelService: TextGenerating {}`.

In `Sources/Verbaine/Model/TokenBudget.swift`, delete the `protocol TokenCounting` block and the line `extension ModelService: TokenCounting {}`.

- [ ] **Step 5: Conform `ModelService`**

In `Sources/Verbaine/Model/ModelService.swift`, add the two missing members next to the existing `availability` and `contextSize`, and declare the conformance on the actor:

```swift
actor ModelService: InferenceProvider {
```

```swift
    /// The on-device model is the reason this app exists: nothing it is given leaves the Mac.
    nonisolated var isRemote: Bool { false }

    nonisolated var displayName: String { "Apple on-device" }
```

`respond`, `tokenCount`, `contextSize`, `availability` and `stream` already match the protocol and need no change. `stream` is already `nonisolated`-compatible — if the compiler complains that it is actor-isolated, mark it `nonisolated`; it captures only `model`, which is a `let`.

- [ ] **Step 6: Create the resolver**

Create `Sources/Verbaine/Model/Inference.swift`:

```swift
import Foundation

/// The provider every action runs against.
///
/// Resolved per call rather than cached: switching providers in Settings has to take effect on the
/// next action, not the next launch. Resolution is cheap — the on-device case returns a singleton,
/// and the remote case builds a struct around `URLSession.shared`.
enum Inference {
    static var current: any InferenceProvider { ModelService.shared }
}
```

Task 2 replaces the body. Keeping it a one-liner here is what makes this task a provable no-op.

- [ ] **Step 7: Widen the convenience initialisers**

In `Sources/Verbaine/Model/TokenBudget.swift`:

```swift
    init(service: any InferenceProvider = Inference.current) {
        self.init(contextSize: service.contextSize, counter: service)
    }
```

In `Sources/Verbaine/Model/ParagraphRewriter.swift`:

```swift
    init(service: any InferenceProvider = Inference.current) {
        self.init(generator: service, budget: TokenBudget(service: service), chunker: TextChunker(service: service))
    }
```

Apply the identical change — `service: ModelService = .shared` becomes `service: any InferenceProvider = Inference.current` — to the convenience `init` in `Sources/Verbaine/Model/TextChunker.swift` and `Sources/Verbaine/Model/MapReduceSummarizer.swift`. Their bodies stay exactly as they are.

- [ ] **Step 8: Move the direct call sites**

Replace `ModelService.shared` with `Inference.current` at these five sites, changing nothing else on the line:

- `Sources/Verbaine/UI/PopoverModel.swift:45` — `tokenCount(for: selection.text)`
- `Sources/Verbaine/UI/PopoverModel.swift:67` — `UserFacingError(Inference.current.availability)`
- `Sources/Verbaine/UI/PopoverModel.swift:96` — `await Inference.current.stream(...)`
- `Sources/Verbaine/Model/CustomAction.swift:43-44` — both the `availability` guard and the `tokenCount` call
- `Sources/Verbaine/App/ServicesProvider.swift:62` — `respond(instructions:prompt:)`

In `Sources/Verbaine/App/DebugMenu.swift`, move lines 13, 70, 104 and 108 the same way.

**Leave `Sources/Verbaine/Onboarding/OnboardingModel.swift:30` on `ModelService.shared`.** Onboarding exists to get Apple Intelligence switched on; a configured remote key must not satisfy that gate. Add a comment on that line saying so:

```swift
        // Deliberately not `Inference.current`: onboarding is about Apple Intelligence being on,
        // and a configured remote endpoint must not make that step look finished.
        availability = ModelService.shared.availability
```

- [ ] **Step 10: Run the full suite**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' build` then the `test` command.
Expected: build succeeds; all 115 existing tests plus the 2 new ones pass. Any existing test that fails here is a refactor mistake, not a stale expectation — fix the source, not the test.

- [ ] **Step 11: Commit**

```bash
git add Sources/Verbaine/Model/InferenceProvider.swift Sources/Verbaine/Model/Inference.swift \
        Sources/Verbaine/Model/ModelService.swift Sources/Verbaine/Model/TokenBudget.swift \
        Sources/Verbaine/Model/ParagraphRewriter.swift Sources/Verbaine/Model/TextChunker.swift \
        Sources/Verbaine/Model/MapReduceSummarizer.swift Sources/Verbaine/UI/PopoverModel.swift \
        Sources/Verbaine/Model/CustomAction.swift Sources/Verbaine/App/ServicesProvider.swift \
        Sources/Verbaine/App/DebugMenu.swift Sources/Verbaine/Onboarding/OnboardingModel.swift \
        Tests/VerbaineTests/InferenceTests.swift
git commit -m "refactor: route inference through an InferenceProvider protocol (T3.6)"
```

---

### Task 2: Remote configuration, Keychain storage, and the Settings tab

Everything the user fills in, with nothing yet consuming it. `Inference.current` still returns the on-device provider at the end of this task — Task 3 flips it.

**Files:**
- Create: `Sources/Verbaine/Model/Remote/RemoteConfig.swift`
- Create: `Sources/Verbaine/Model/Remote/APIKeyStore.swift`
- Create: `Sources/Verbaine/Settings/ModelSettings.swift`
- Modify: `Sources/Verbaine/Settings/SettingsView.swift:7-18` (add the tab)
- Test: `Tests/VerbaineTests/RemoteConfigTests.swift`, `Tests/VerbaineTests/APIKeyStoreTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 beyond it having landed.
- Produces:
  - `enum InferenceProviderKind: String, CaseIterable, Sendable, Identifiable { case apple, remote }`
  - `struct RemoteConfig: Equatable, Sendable { var baseURL: String; var model: String; var contextSize: Int; var isComplete: Bool; var endpointURL: URL? }`
  - `Preferences.providerKind(_:) -> InferenceProviderKind`, `Preferences.setProviderKind(_:_:)`, `Preferences.remoteConfig(_:) -> RemoteConfig`, `Preferences.setRemoteConfig(_:_:)`, and the keys `Preferences.providerKindKey`, `Preferences.remoteBaseURLKey`, `Preferences.remoteModelKey`, `Preferences.remoteContextSizeKey`
  - `enum APIKeyStore { static func save(_ key: String, forHost: String) throws; static func load(forHost: String) -> String?; static func delete(forHost: String) throws }`

- [ ] **Step 1: Write the failing config test**

Create `Tests/VerbaineTests/RemoteConfigTests.swift`:

```swift
import Foundation
import Testing
@testable import Verbaine

/// A defaults domain of its own per test, so nothing touches the real preferences.
private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "verbaine.tests.\(UUID().uuidString)")!
}

@Test("the provider falls back to the on-device model and round-trips")
func providerKindPersists() {
    let defaults = scratchDefaults()
    #expect(Preferences.providerKind(defaults) == .apple)

    Preferences.setProviderKind(.remote, defaults)
    #expect(Preferences.providerKind(defaults) == .remote)

    // A value written by an older or newer build must not strand the user on a provider the app
    // cannot resolve.
    defaults.set("anthropic-native", forKey: Preferences.providerKindKey)
    #expect(Preferences.providerKind(defaults) == .apple)
}

@Test("a remote config round-trips and defaults to a 128k window")
func remoteConfigPersists() {
    let defaults = scratchDefaults()
    #expect(Preferences.remoteConfig(defaults).contextSize == 128_000)
    #expect(Preferences.remoteConfig(defaults).isComplete == false)

    let config = RemoteConfig(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", contextSize: 128_000)
    Preferences.setRemoteConfig(config, defaults)
    #expect(Preferences.remoteConfig(defaults) == config)
    #expect(Preferences.remoteConfig(defaults).isComplete)
}

@Test("a config is incomplete until both the URL and the model name are filled in", arguments: [
    ("", "gpt-4o-mini"),
    ("https://api.openai.com/v1", ""),
    ("   ", "   "),
])
func incompleteConfig(baseURL: String, model: String) {
    let config = RemoteConfig(baseURL: baseURL, model: model, contextSize: 128_000)
    #expect(config.isComplete == false)
}

@Test("the chat endpoint is built from the base URL, with or without a trailing slash", arguments: [
    "https://api.openai.com/v1",
    "https://api.openai.com/v1/",
])
func endpointURL(baseURL: String) {
    let config = RemoteConfig(baseURL: baseURL, model: "gpt-4o-mini", contextSize: 128_000)
    #expect(config.endpointURL?.absoluteString == "https://api.openai.com/v1/chat/completions")
}

@Test("a base URL that is not a URL yields no endpoint rather than a crash")
func endpointURLRejectsGarbage() {
    let config = RemoteConfig(baseURL: "not a url at all", model: "gpt-4o-mini", contextSize: 128_000)
    #expect(config.endpointURL == nil)
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: FAIL to compile — "cannot find 'RemoteConfig' in scope".

- [ ] **Step 3: Write `RemoteConfig`**

Create `Sources/Verbaine/Model/Remote/RemoteConfig.swift`:

```swift
import Foundation

/// Which backend runs the actions. Raw values persist in `UserDefaults`.
enum InferenceProviderKind: String, CaseIterable, Sendable, Identifiable {
    case apple, remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple on-device"
        case .remote: "Custom endpoint"
        }
    }
}

/// Where a remote provider lives and what to ask it for. The API key is deliberately not here —
/// it lives in the Keychain, via `APIKeyStore`, and nothing in this struct is secret.
struct RemoteConfig: Equatable, Sendable {
    /// e.g. `https://api.openai.com/v1`. Stored as typed, validated on use.
    var baseURL: String
    /// e.g. `gpt-4o-mini`. Free text: every endpoint names its models differently, and some have
    /// no way to list them.
    var model: String
    /// What the user says this model's window is. Declared rather than discovered — no
    /// OpenAI-compatible endpoint reports it.
    var contextSize: Int

    static let defaultContextSize = 128_000

    /// Enough filled in to be worth trying. The key is checked separately, at call time, because
    /// it is keyed by host and the host comes from `baseURL`.
    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The host the API key is filed under, so switching endpoints cannot silently reuse another
    /// endpoint's key.
    var host: String? {
        URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host()
    }

    /// The chat-completions URL. `nil` when `baseURL` is not a URL at all.
    var endpointURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host() != nil else { return nil }
        return url.appending(path: "chat/completions")
    }
}
```

`URL.appending(path:)` collapses a trailing slash on its own, which is why both spellings in the test produce the same endpoint.

- [ ] **Step 4: Add the `Preferences` accessors**

Append to `Sources/Verbaine/Settings/Preferences.swift`, following the file's existing extension-per-topic layout:

```swift
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
            contextSize: defaults.object(forKey: remoteContextSizeKey) as? Int ?? RemoteConfig.defaultContextSize
        )
    }

    static func setRemoteConfig(_ config: RemoteConfig, _ defaults: UserDefaults = .standard) {
        defaults.set(config.baseURL.trimmingCharacters(in: .whitespaces), forKey: remoteBaseURLKey)
        defaults.set(config.model.trimmingCharacters(in: .whitespaces), forKey: remoteModelKey)
        defaults.set(max(1, config.contextSize), forKey: remoteContextSizeKey)
    }
}
```

- [ ] **Step 5: Run the config tests**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: PASS, all config tests green.

- [ ] **Step 6: Write the failing Keychain test**

Create `Tests/VerbaineTests/APIKeyStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import Verbaine

/// A host nobody will ever configure, so the test cannot collide with a real stored key.
private func scratchHost() -> String { "test-\(UUID().uuidString).invalid" }

@Test("a key saves, loads back, overwrites and deletes")
func keyRoundTrips() throws {
    let host = scratchHost()
    defer { try? APIKeyStore.delete(forHost: host) }

    #expect(APIKeyStore.load(forHost: host) == nil)

    try APIKeyStore.save("sk-first", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == "sk-first")

    // Saving again must replace, not fail with errSecDuplicateItem.
    try APIKeyStore.save("sk-second", forHost: host)
    #expect(APIKeyStore.load(forHost: host) == "sk-second")

    try APIKeyStore.delete(forHost: host)
    #expect(APIKeyStore.load(forHost: host) == nil)
}

@Test("keys for two hosts do not see each other")
func keysAreScopedToHost() throws {
    let first = scratchHost()
    let second = scratchHost()
    defer {
        try? APIKeyStore.delete(forHost: first)
        try? APIKeyStore.delete(forHost: second)
    }

    try APIKeyStore.save("sk-openai", forHost: first)
    try APIKeyStore.save("sk-groq", forHost: second)

    #expect(APIKeyStore.load(forHost: first) == "sk-openai")
    #expect(APIKeyStore.load(forHost: second) == "sk-groq")
}

@Test("deleting a key that was never there is not an error")
func deletingAbsentKeyIsFine() throws {
    try APIKeyStore.delete(forHost: scratchHost())
}
```

- [ ] **Step 7: Run it to verify it fails**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: FAIL to compile — "cannot find 'APIKeyStore' in scope".

- [ ] **Step 8: Write `APIKeyStore`**

Create `Sources/Verbaine/Model/Remote/APIKeyStore.swift`:

```swift
import Foundation
import Security

/// The API key, and only the API key, in the Keychain.
///
/// Filed per endpoint host: pointing Verbaine at a different provider must not silently send the old
/// provider's key to the new one. Nothing here ever returns the key inside an error, and no call
/// site logs the value.
enum APIKeyStore {
    static let service = "in.saswatsaubhagya.verbaine.apikey"

    enum StoreError: Error, Equatable {
        /// The Keychain refused, with its own status code. The code is safe to show; the key is not.
        case keychain(OSStatus)
    }

    private static func query(forHost host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
    }

    /// Replaces any key already stored for `host`.
    static func save(_ key: String, forHost host: String) throws {
        try delete(forHost: host)
        guard !key.isEmpty else { return }

        var attributes = query(forHost: host)
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    /// `nil` for "no key stored" and for any Keychain failure alike: every caller's next move is
    /// the same — tell the user the endpoint is not configured.
    static func load(forHost host: String) -> String? {
        var attributes = query(forHost: host)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deleting a key that is not there succeeds — `save` relies on that to overwrite.
    static func delete(forHost host: String) throws {
        let status = SecItemDelete(query(forHost: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }
}
```

- [ ] **Step 9: Run the Keychain tests**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: PASS. If every Keychain call returns `errSecMissingEntitlement` (-34018), the test bundle is not signed with a Keychain-access group; run the app target once from Xcode and re-run. If it persists, note it in `docs/TESTING.md` as a device-only check rather than weakening the store.

- [ ] **Step 10: Build the Settings tab**

Create `Sources/Verbaine/Settings/ModelSettings.swift`. The Test-connection button calls the provider that does not exist until Task 3, so this step wires the button to a stub that Task 3 replaces — the stub is named in the source so it cannot be forgotten:

```swift
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
```

- [ ] **Step 12: Add the tab**

In `Sources/Verbaine/Settings/SettingsView.swift`, insert between the General and Apps tabs:

```swift
            ModelSettings()
                .tabItem { Label("Model", systemImage: "cpu") }
```

- [ ] **Step 13: Build, run the suite, and check the tab by hand**

Run both `xcodebuild` commands.
Expected: build succeeds, all tests pass.

Then open Settings → Model: the radio defaults to Apple on-device, the remote fields appear only when Custom endpoint is picked, a preset fills the Base URL field, and reopening Settings shows the values you typed still there.

- [ ] **Step 14: Add the manual checklist**

Append to `docs/TESTING.md`, under a `## T3.7 — Model settings` heading:

```markdown
- [ ] Settings → Model defaults to "Apple on-device" on a fresh install.
- [ ] Picking "Custom endpoint" reveals Base URL, API key, Model and Context size.
- [ ] Choosing a preset fills the Base URL field and leaves the other fields alone.
- [ ] Typed values survive closing and reopening Settings.
- [ ] The API key field is masked, and the key does not appear in `defaults read in.saswatsaubhagya.verbaine`.
- [ ] Switching back to "Apple on-device" hides the fields but keeps the stored values.
```

- [ ] **Step 15: Commit**

```bash
git add Sources/Verbaine/Model/Remote/RemoteConfig.swift Sources/Verbaine/Model/Remote/APIKeyStore.swift \
        Sources/Verbaine/Settings/ModelSettings.swift Sources/Verbaine/Settings/SettingsView.swift \
        Sources/Verbaine/Settings/Preferences.swift Tests/VerbaineTests/RemoteConfigTests.swift \
        Tests/VerbaineTests/APIKeyStoreTests.swift docs/TESTING.md
git commit -m "feat: remote endpoint settings and Keychain key storage (T3.7)"
```

---

### Task 3: The OpenAI-compatible provider

**Files:**
- Create: `Sources/Verbaine/Model/Remote/RemoteError.swift`
- Create: `Sources/Verbaine/Model/Remote/SSEStream.swift`
- Create: `Sources/Verbaine/Model/Remote/OpenAICompatibleProvider.swift`
- Modify: `Sources/Verbaine/Model/Inference.swift` (resolve to the remote provider)
- Modify: `Sources/Verbaine/UI/UserFacingError.swift` (map `RemoteError`, add the `.modelSettings` remedy)
- Modify: `Sources/Verbaine/UI/PopoverView.swift:29-44`, `Sources/Verbaine/UI/PopoverPanel.swift:70-82` (handle the new remedy)
- Modify: `Sources/Verbaine/Model/ContextRetry.swift:13-21` (recognise the remote context error)
- Modify: `Sources/Verbaine/Settings/ModelSettings.swift` (`runTest` does a real round trip)
- Test: `Tests/VerbaineTests/SSEStreamTests.swift`, `Tests/VerbaineTests/RemoteErrorTests.swift`, `Tests/VerbaineTests/RemoteBudgetTests.swift`

**Interfaces:**
- Consumes: `RemoteConfig`, `APIKeyStore`, `Preferences.providerKind`, `Preferences.remoteConfig` from Task 2; `InferenceProvider` and `Inference` from Task 1.
- Produces:
  - `enum RemoteError: Error, Equatable { case notConfigured, unauthorized, modelNotFound, rateLimited, serverError, unreachable, contextLengthExceeded, malformedResponse }` with `static func from(status: Int, body: String) -> RemoteError`
  - `enum SSEStream { enum Event: Equatable { case content(String), done, ignore }; static func event(from line: String) -> Event; static func snapshots<S>(lines: S) -> AsyncThrowingStream<String, any Error> }`
  - `struct OpenAICompatibleProvider: InferenceProvider { init(config: RemoteConfig, apiKey: String, session: URLSession = .shared) }`
  - `UserFacingError.Remedy.modelSettings`

- [ ] **Step 1: Write the failing SSE test**

Create `Tests/VerbaineTests/SSEStreamTests.swift`:

```swift
import Foundation
import Testing
@testable import Verbaine

/// Replays a fixed list of lines, as `URLSession.bytes(for:).lines` would deliver them.
private struct StubLines: AsyncSequence, Sendable {
    let lines: [String]

    struct AsyncIterator: AsyncIteratorProtocol {
        var remaining: [String]
        mutating func next() async throws -> String? {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(remaining: lines) }
}

@Test("a content delta is read out of a data line")
func readsContentDelta() {
    let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
    #expect(SSEStream.event(from: line) == .content("Hello"))
}

@Test("the terminator ends the stream")
func readsDone() {
    #expect(SSEStream.event(from: "data: [DONE]") == .done)
}

@Test("noise between events is ignored, never thrown", arguments: [
    "",
    ": keep-alive",
    "event: message",
    #"data: {"choices":[{"delta":{}}]}"#,
    #"data: {"choices":[]}"#,
    "data: not json at all",
])
func ignoresNoise(line: String) {
    #expect(SSEStream.event(from: line) == .ignore)
}

@Test("snapshots are cumulative, matching what the on-device stream yields")
func snapshotsAccumulate() async throws {
    let lines = StubLines(lines: [
        #"data: {"choices":[{"delta":{"content":"Fix "}}]}"#,
        ": keep-alive",
        #"data: {"choices":[{"delta":{"content":"the "}}]}"#,
        #"data: {"choices":[{"delta":{"content":"grammar."}}]}"#,
        "data: [DONE]",
    ])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received == ["Fix ", "Fix the ", "Fix the grammar."])
}

@Test("a stream that ends without [DONE] still finishes with everything it received")
func snapshotsSurviveMissingTerminator() async throws {
    let lines = StubLines(lines: [#"data: {"choices":[{"delta":{"content":"Half"}}]}"#])

    var received: [String] = []
    for try await snapshot in SSEStream.snapshots(lines: lines) { received.append(snapshot) }

    #expect(received == ["Half"])
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: FAIL to compile — "cannot find 'SSEStream' in scope".

- [ ] **Step 3: Write `SSEStream`**

Create `Sources/Verbaine/Model/Remote/SSEStream.swift`:

```swift
import Foundation

/// Turns an OpenAI-compatible server-sent-event stream into the cumulative snapshots the popover
/// already knows how to render.
///
/// ponytail: this parses lines, not bytes. `URLSession.bytes(for:).lines` already reassembles a
/// JSON object split across two network chunks, so there is no buffer to get wrong here.
enum SSEStream {
    enum Event: Equatable {
        case content(String)
        case done
        /// Keep-alives, comments, empty deltas and anything unparseable. A malformed line is never
        /// fatal — the provider is not ours, and one bad frame must not lose the answer so far.
        case ignore
    }

    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    static func event(from line: String) -> Event {
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let content = chunk.choices.first?.delta?.content,
              !content.isEmpty
        else { return .ignore }
        return .content(content)
    }

    /// Yields the whole answer so far after every delta — the same contract `ResponseStream` has,
    /// so the result pane and the word-level diff need no remote-specific branch.
    static func snapshots<S: AsyncSequence & Sendable>(
        lines: S
    ) -> AsyncThrowingStream<String, any Error> where S.Element == String, S.AsyncIterator: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var answer = ""
                    for try await line in lines {
                        switch event(from: line) {
                        case .content(let delta):
                            answer += delta
                            continuation.yield(answer)
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

If the compiler rejects the `S.AsyncIterator: Sendable` constraint against `URLSession.AsyncBytes.Lines`, drop that clause and keep `S: AsyncSequence & Sendable` alone.

- [ ] **Step 4: Run the SSE tests**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: PASS, all six SSE tests green.

- [ ] **Step 5: Write the failing error-mapping test**

Create `Tests/VerbaineTests/RemoteErrorTests.swift`:

```swift
import Foundation
import Testing
@testable import Verbaine

@Test("every HTTP status the endpoints actually return maps to its own failure", arguments: [
    (401, RemoteError.unauthorized),
    (403, .unauthorized),
    (404, .modelNotFound),
    (429, .rateLimited),
    (500, .serverError),
    (503, .serverError),
])
func mapsStatus(status: Int, expected: RemoteError) {
    #expect(RemoteError.from(status: status, body: "") == expected)
}

@Test("a 400 naming the model is a model problem, not a generic one")
func mapsModelNotFound() {
    let body = #"{"error":{"message":"The model `gpt-9` does not exist","code":"model_not_found"}}"#
    #expect(RemoteError.from(status: 400, body: body) == .modelNotFound)
}

@Test("a 400 about the window routes into the existing halve-and-retry backstop")
func mapsContextLengthExceeded() {
    let body = #"{"error":{"message":"maximum context length","code":"context_length_exceeded"}}"#
    #expect(RemoteError.from(status: 400, body: body) == .contextLengthExceeded)
    #expect(ContextRetry.isContextSizeExceeded(RemoteError.contextLengthExceeded))
}

@Test("an unrecognised 400 is a server error rather than a silent success")
func mapsUnknown400() {
    #expect(RemoteError.from(status: 400, body: "{}") == .serverError)
}

@Test("every remote failure reaches the user as a sentence and one thing to do", arguments: [
    RemoteError.notConfigured,
    .unauthorized,
    .modelNotFound,
    .rateLimited,
    .serverError,
    .unreachable,
    .malformedResponse,
])
func everyRemoteErrorHasAMessage(error: RemoteError) {
    let shown = UserFacingError(error)
    #expect(!shown.message.isEmpty)
    #expect(shown.message.hasSuffix(".") || shown.message.hasSuffix("?"))
}

@Test("a key problem points the user at the Model tab")
func keyProblemsOpenSettings() {
    #expect(UserFacingError(RemoteError.unauthorized).remedy == .modelSettings)
    #expect(UserFacingError(RemoteError.modelNotFound).remedy == .modelSettings)
    #expect(UserFacingError(RemoteError.notConfigured).remedy == .modelSettings)
}

@Test("a URLSession failure is reported as unreachable, not as a generic retry")
func mapsURLError() {
    let shown = UserFacingError(URLError(.notConnectedToInternet))
    #expect(shown == UserFacingError(RemoteError.unreachable))
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: FAIL to compile — "cannot find 'RemoteError' in scope".

- [ ] **Step 7: Write `RemoteError`**

Create `Sources/Verbaine/Model/Remote/RemoteError.swift`:

```swift
import Foundation

/// What a remote endpoint can do to us, in the app's own vocabulary.
///
/// The endpoint is not ours and its error bodies vary, so the HTTP status carries most of the
/// meaning and the body is only consulted to tell three different 400s apart.
enum RemoteError: Error, Equatable {
    /// No base URL, no model name, or no key stored for that host.
    case notConfigured
    case unauthorized
    case modelNotFound
    case rateLimited
    case serverError
    /// Offline, DNS, TLS, timeout — anything `URLSession` itself refused.
    case unreachable
    /// The input did not fit the model's window, per the endpoint. Feeds `ContextRetry`.
    case contextLengthExceeded
    /// A 200 whose body was not a chat completion.
    case malformedResponse

    /// `body` is the raw response text. It is matched case-insensitively and never shown to the
    /// user or logged — some providers echo request content back inside error messages.
    static func from(status: Int, body: String) -> RemoteError {
        switch status {
        case 401, 403:
            return .unauthorized
        case 404:
            return .modelNotFound
        case 429:
            return .rateLimited
        case 400:
            let lowered = body.lowercased()
            if lowered.contains("context_length_exceeded") || lowered.contains("maximum context length") {
                return .contextLengthExceeded
            }
            if lowered.contains("model_not_found") || lowered.contains("does not exist") {
                return .modelNotFound
            }
            return .serverError
        default:
            return .serverError
        }
    }
}
```

- [ ] **Step 8: Add the unconfigured-endpoint availability case**

`ModelAvailability` today only describes ways Apple Intelligence can be missing, so an
unconfigured endpoint would tell the user their Mac cannot run Apple Intelligence — wrong, and
un-actionable. Add a case in `Sources/Verbaine/Model/ModelAvailability.swift`:

```swift
    /// A custom endpoint is selected but its URL, model name or key is missing. Only a remote
    /// provider ever reports this; `init(_:)` below never produces it, because the framework has
    /// no such concept.
    case remoteNotConfigured
```

`init(_ availability: SystemLanguageModel.Availability)` stays exactly as it is — nothing maps to
the new case. Then extend the availability mapping in `Sources/Verbaine/UI/UserFacingError.swift`:

```swift
        case .remoteNotConfigured:
            self.init(
                message: "Add a base URL, model name and API key in Settings to use a custom endpoint.",
                remedy: .modelSettings
            )
```

If `Sources/Verbaine/App/DebugErrors.swift:52` enumerates availability cases for the debug menu, add
`("Remote not configured", ModelAvailability.remoteNotConfigured)` to that list so the debug menu
stays exhaustive.

- [ ] **Step 9: Map `RemoteError` to `UserFacingError`**

In `Sources/Verbaine/UI/UserFacingError.swift`, add the remedy case alongside the existing ones:

```swift
        /// The endpoint the user configured needs fixing — open Settings at the Model tab.
        case modelSettings
```

Add its button title in `Remedy.title`:

```swift
        case .modelSettings: "Open Settings"
```

Add the branch to `init(_ error: any Error)`, above the `default:` case:

```swift
        case let error as RemoteError:
            self = UserFacingError(error)
        case is URLError:
            self = UserFacingError(RemoteError.unreachable)
```

And add the mapping initialiser next to the existing per-domain ones:

```swift
    /// A remote endpoint's failure. The endpoint is the user's own, so every message says which of
    /// the four fields in Settings to go and look at.
    init(_ error: RemoteError) {
        switch error {
        case .notConfigured:
            self.init(
                message: "Add a base URL, model name and API key in Settings to use a custom endpoint.",
                remedy: .modelSettings
            )
        case .unauthorized:
            self.init(
                message: "Your endpoint rejected the API key. Check it in Settings.",
                remedy: .modelSettings
            )
        case .modelNotFound:
            self.init(
                message: "Your endpoint does not recognise that model name. Check it in Settings.",
                remedy: .modelSettings
            )
        case .rateLimited:
            self.init(
                message: "Your provider is rate-limiting this key. Try again shortly.",
                remedy: .retry
            )
        case .serverError:
            self.init(
                message: "Your endpoint returned an error. Try again shortly.",
                remedy: .retry
            )
        case .unreachable:
            self.init(
                message: "Verbaine could not reach your endpoint. Check your connection and the base URL.",
                remedy: .modelSettings
            )
        case .contextLengthExceeded:
            self = Self.tooLong
        case .malformedResponse:
            self.init(
                message: "Your endpoint sent a reply Verbaine could not read.",
                remedy: .retry
            )
        }
    }
```

Add `openVerbaineSettings` to the `SettingsPane` enum at the bottom of the same file:

```swift
    /// Verbaine's own Settings window, for the remedies that point at the Model tab.
    static func openVerbaineSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
```

- [ ] **Step 10: Handle the new remedy at both switch sites**

Both switches over `Remedy` are exhaustive and will now fail to compile — that is the point.

In `Sources/Verbaine/UI/PopoverView.swift`, inside `apply(_:)`:

```swift
        case .modelSettings:
            SettingsPane.openVerbaineSettings()
            model.onClose()
```

In `Sources/Verbaine/UI/PopoverPanel.swift`, inside the `perform:` closure:

```swift
                case .modelSettings:
                    SettingsPane.openVerbaineSettings()
```

- [ ] **Step 11: Teach `ContextRetry` the third vocabulary**

In `Sources/Verbaine/Model/ContextRetry.swift`, add to `isContextSizeExceeded(_:)`, before `return false`:

```swift
        if let error = error as? RemoteError, error == .contextLengthExceeded { return true }
```

Update that function's doc comment: "in any of the three vocabularies `UserFacingError` maps".

- [ ] **Step 12: Run the error tests**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: PASS, all error-mapping tests green, and the existing `UserFacingErrorTests` and `ContextRetryTests` still green.

- [ ] **Step 13: Write the failing budget test**

Create `Tests/VerbaineTests/RemoteBudgetTests.swift`:

```swift
import Foundation
import Testing
@testable import Verbaine

private func provider(contextSize: Int = 128_000) -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(
        config: RemoteConfig(baseURL: "https://api.example.com/v1", model: "test-model", contextSize: contextSize),
        apiKey: "sk-test"
    )
}

@Test("the remote token count is a four-characters-per-token estimate")
func estimatesTokens() async throws {
    let text = String(repeating: "a", count: 400)
    #expect(try await provider().tokenCount(for: text) == 100)
}

@Test("an empty string costs nothing")
func estimatesEmpty() async throws {
    #expect(try await provider().tokenCount(for: "") == 0)
}

@Test("at a 128k window a long document is one pass, so chunking never fires")
func longTextIsSinglePass() async throws {
    // ~4,000 words of prose, far past anything the on-device model could take in one call.
    let text = String(repeating: "word ", count: 4_000)
    #expect(try await TokenBudget(service: provider()).fitsInOnePass(action: .improve, text: text))
}

@Test("a small declared window still chunks, so a local 8k model is not silently truncated")
func smallWindowStillChunks() async throws {
    let text = String(repeating: "word ", count: 4_000)
    #expect(try await TokenBudget(service: provider(contextSize: 8_000)).fitsInOnePass(action: .improve, text: text) == false)
}

@Test("a provider with no key says it is unconfigured, not that the Mac is unsupported")
func missingKeyIsUnconfigured() {
    let config = RemoteConfig(baseURL: "https://api.example.com/v1", model: "test-model", contextSize: 128_000)
    let provider = OpenAICompatibleProvider(config: config, apiKey: "")
    #expect(provider.availability == .remoteNotConfigured)
    #expect(UserFacingError(provider.availability)?.remedy == .modelSettings)
}

@Test("the remote provider announces itself as remote, by model name")
func remoteProviderIdentifiesItself() {
    #expect(provider().isRemote)
    #expect(provider().displayName == "test-model")
}
```

- [ ] **Step 14: Run it to verify it fails**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: FAIL to compile — "cannot find 'OpenAICompatibleProvider' in scope".

- [ ] **Step 15: Write the provider**

Create `Sources/Verbaine/Model/Remote/OpenAICompatibleProvider.swift`:

```swift
import Foundation
import os

/// One `InferenceProvider` for every endpoint that speaks OpenAI's `/chat/completions` — OpenAI,
/// Anthropic's compatibility layer, OpenRouter, Groq, Together, Ollama, LM Studio, vLLM.
///
/// There is deliberately no per-vendor code: the base URL, the model name and the key come from
/// Settings, and everything else is the same wire format. One request per action, `messages`
/// rebuilt from scratch every time, so no transcript is ever carried between actions.
struct OpenAICompatibleProvider: InferenceProvider {
    private let config: RemoteConfig
    private let apiKey: String
    private let session: URLSession
    private let log = Logger(subsystem: "in.saswatsaubhagya.verbaine", category: "RemoteProvider")

    init(config: RemoteConfig, apiKey: String, session: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
    }

    var isRemote: Bool { true }

    var displayName: String { config.model }

    var contextSize: Int { config.contextSize }

    var availability: ModelAvailability {
        isConfigured ? .ready : .remoteNotConfigured
    }

    private var isConfigured: Bool {
        config.isComplete && config.endpointURL != nil && !apiKey.isEmpty
    }

    /// Four characters per token, the usual English rule of thumb.
    ///
    /// ponytail: an estimate, not a count. Real tokenizers are per-vendor and per-version, and at a
    /// 128k declared window the estimate never changes the single-pass verdict. If a user reports
    /// truncation on a small local model, the upgrade is a bundled BPE table here, nowhere else.
    func tokenCount(for text: String) async throws -> Int {
        text.count / 4
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        var answer = ""
        for try await snapshot in stream(instructions: instructions, prompt: prompt) {
            answer = snapshot
        }
        guard !answer.isEmpty else { throw RemoteError.malformedResponse }
        return answer
    }

    func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(instructions: instructions, prompt: prompt)
                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // The body carries the only thing that tells three different 400s apart.
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw RemoteError.from(status: http.statusCode, body: body)
                    }

                    for try await snapshot in SSEStream.snapshots(lines: bytes.lines) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as RemoteError {
                    continuation.finish(throwing: error)
                } catch {
                    // Never surface the underlying description: some URLErrors embed the URL, and
                    // a mistyped key can end up in a URL.
                    log.error("remote request failed: \(error._domain) \(error._code)")
                    continuation.finish(throwing: RemoteError.unreachable)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(instructions: String, prompt: String) throws -> URLRequest {
        guard isConfigured, let url = config.endpointURL else { throw RemoteError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: any Sendable] = [
            "model": config.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
```

- [ ] **Step 16: Resolve to it**

Replace the body of `Inference.current` in `Sources/Verbaine/Model/Inference.swift`:

```swift
enum Inference {
    static var current: any InferenceProvider {
        guard Preferences.providerKind() == .remote else { return ModelService.shared }

        let config = Preferences.remoteConfig()
        guard let host = config.host, let key = APIKeyStore.load(forHost: host) else {
            // Configured as remote but the key is gone — a Keychain reset, or a base URL edited
            // after the key was saved. Falling back to the on-device model would quietly send the
            // text somewhere the user did not choose, so hand back a provider that explains itself.
            return OpenAICompatibleProvider(config: config, apiKey: "")
        }
        return OpenAICompatibleProvider(config: config, apiKey: key)
    }
}
```

`InferenceTests.defaultProviderIsApple` still passes: `providerKind` defaults to `.apple`.

- [ ] **Step 17: Run the budget tests**

Run: `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test`
Expected: PASS. No test in this task opens a socket — `OpenAICompatibleProvider` is exercised only through `tokenCount`, `availability`, `displayName` and `TokenBudget`.

- [ ] **Step 18: Wire up Test connection**

In `Sources/Verbaine/Settings/ModelSettings.swift`, replace `runTest()`:

```swift
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
```

- [ ] **Step 19: Build and check by hand against a real endpoint**

Run both `xcodebuild` commands. Expected: build succeeds, all tests pass.

Then, with a real key: Settings → Model → Custom endpoint, fill in a base URL, key and model, press Test connection. Expect "Reached it". Break the key by a character and press it again: expect "Your endpoint rejected the API key. Check it in Settings." Break the model name: expect the model message. Turn off Wi-Fi: expect the unreachable message.

- [ ] **Step 20: Commit**

```bash
git add Sources/Verbaine/Model/Remote/RemoteError.swift Sources/Verbaine/Model/Remote/SSEStream.swift \
        Sources/Verbaine/Model/Remote/OpenAICompatibleProvider.swift Sources/Verbaine/Model/Inference.swift \
        Sources/Verbaine/Model/ContextRetry.swift Sources/Verbaine/Model/ModelAvailability.swift \
        Sources/Verbaine/UI/UserFacingError.swift Sources/Verbaine/App/DebugErrors.swift \
        Sources/Verbaine/UI/PopoverView.swift Sources/Verbaine/UI/PopoverPanel.swift \
        Sources/Verbaine/Settings/ModelSettings.swift Tests/VerbaineTests/SSEStreamTests.swift \
        Tests/VerbaineTests/RemoteErrorTests.swift Tests/VerbaineTests/RemoteBudgetTests.swift
git commit -m "feat: OpenAI-compatible remote provider with SSE streaming (T3.8)"
```

---

### Task 4: Make the remote case visible, and legal

Nothing sends anything off the Mac until this task lands the entitlement — until now the requests fail inside the sandbox. That is deliberate: the visibility work and the permission to send arrive together.

**Files:**
- Modify: `Verbaine.entitlements`
- Modify: `Sources/Verbaine/Resources/PrivacyInfo.xcprivacy`
- Modify: `Sources/Verbaine/App/VerbaineApp.swift:9`
- Modify: `Sources/Verbaine/UI/PopoverView.swift` (badge under the action grid)
- Modify: `docs/PRD.md` (goal 3, the Network permission row, the Privacy posture bullet)
- Modify: `docs/TESTING.md`, `docs/TASKS.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: `Preferences.providerKindKey`, `Preferences.remoteConfig`, `Inference.current.isRemote`, `Inference.current.displayName`.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Add the network entitlement**

In `Verbaine.entitlements`, inside the `<dict>`:

```xml
	<key>com.apple.security.network.client</key>
	<true/>
```

Outgoing connections only. Do not add `network.server`.

- [ ] **Step 2: Swap the menu-bar symbol when remote is active**

In `Sources/Verbaine/App/VerbaineApp.swift`, add the stored preference and switch the symbol. `@AppStorage` is what makes this update the moment the radio changes, with no notification to wire up:

```swift
@main
struct VerbaineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Drives the menu-bar symbol. Reading the preference directly rather than
    /// `Inference.current.isRemote` keeps this a value SwiftUI can observe.
    @AppStorage(Preferences.providerKindKey) private var providerKind = InferenceProviderKind.apple

    var body: some Scene {
        MenuBarExtra("Verbaine", systemImage: providerKind == .remote ? "wand.and.sparkles.inverse" : "wand.and.sparkles") {
```

A filled symbol rather than a tint: menu-bar labels are template-rendered, so a `foregroundStyle` would be ignored, and the two symbols are the same shape at a glance while being unmistakable side by side.

- [ ] **Step 3: Badge the popover**

In `Sources/Verbaine/UI/PopoverView.swift`, add the badge below `actionGrid` in the `.actions` case:

```swift
            case .actions:
                actionGrid
                if Inference.current.isRemote {
                    Label("via \(Inference.current.displayName) · cloud", systemImage: "cloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

It reads `Inference.current` fresh each time the popover is built, which is every invocation — there is no stale case.

- [ ] **Step 4: Update the privacy manifest**

In `Sources/Verbaine/Resources/PrivacyInfo.xcprivacy`, add a collected-data-type entry for other user content, linked to app functionality, not used for tracking:

```xml
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>
```

Keep `NSPrivacyTracking` `false` and the existing tracking-domains array empty — Verbaine still tracks nothing. If the file already has an empty `NSPrivacyCollectedDataTypes` array, replace it rather than adding a second key.

- [ ] **Step 5: Amend the PRD**

In `docs/PRD.md`, replace goal 3 (line 31):

```markdown
3. On-device by default. Text leaves the Mac only when the user configures their own API endpoint in Settings, and the menu-bar icon and popover say so whenever that is active.
```

Replace the Network row of the permissions table (line 260):

```markdown
| Network | Outgoing only (`com.apple.security.network.client`), and only to the endpoint the user configures. Unused when running on-device, which is the default | Never prompted — macOS does not gate outgoing connections |
```

Replace the first Privacy posture bullet (line 264):

```markdown
- Inference is on-device via Foundation Models by default; text never leaves the Mac and is never logged in release builds. A user who configures their own OpenAI-compatible endpoint sends selected text to that endpoint instead, and only then. The API key is stored in the Keychain and is never logged.
```

Add to the "Out of scope" list, so the subscription question does not get re-opened:

```markdown
- Using a ChatGPT or Claude consumer subscription in place of an API key. Consumer chat subscriptions grant no API access, so there is nothing for a third-party app to call.
```

- [ ] **Step 6: Update the repo docs**

In `CLAUDE.md`, under Architecture, extend layer 2:

```markdown
2. **Model** (`Model/`) — `InferenceProvider` is the seam: `ModelService` (actor over `SystemLanguageModel.default`, the default) and `OpenAICompatibleProvider` (`Model/Remote/`, the user's own endpoint) both conform, and `Inference.current` resolves one per call from `Preferences`. `TokenBudget` decides single-pass vs chunked; `TextChunker` (NLTokenizer) splits on paragraph then sentence boundaries, never mid-sentence. Rewrites go paragraph-by-paragraph; summaries use map-reduce with the previous chunk's summary carried forward. Remote token counts are a chars/4 estimate against a user-declared window — exact counting only exists for the on-device model.
```

Add to Non-negotiable constraints:

```markdown
- The remote API key lives in the Keychain only, keyed by endpoint host. Never in `UserDefaults`, never in a log line, never in a user-facing message.
```

In `docs/TASKS.md`, add the four tasks after T3.4 and mark each done with its commit hash as it lands:

```markdown
**T3.6 Inference provider seam** — `InferenceProvider` protocol, `Inference.current` resolver, all call sites moved. Pure refactor.
- Done when: build and test pass with the existing suite unchanged, and `Inference.current` returns the on-device model by default.

**T3.7 Remote endpoint settings** — `RemoteConfig`, `APIKeyStore` (Keychain), Settings "Model" tab with presets and Test connection.
- Done when: values round-trip through Settings, and the key is absent from `defaults read in.saswatsaubhagya.verbaine`.

**T3.8 OpenAI-compatible provider** — `OpenAICompatibleProvider`, `SSEStream`, `RemoteError` mapping, `ContextRetry` extension.
- Done when: a real key streams a rewrite into the popover, and a wrong key, wrong model and offline machine each produce their own message.

**T3.9 Remote visibility and entitlement** — menu-bar symbol, popover badge, network entitlement, privacy manifest, PRD amendment.
- Done when: the icon and badge change with the setting, and `codesign -d --entitlements - ` on the built app shows `network.client`.
```

- [ ] **Step 7: Add the manual checklist**

Append to `docs/TESTING.md` under `## T3.9 — Remote visibility`:

```markdown
- [ ] With Apple on-device selected, the menu-bar icon is the outline wand and the popover shows no badge.
- [ ] Switching to a configured custom endpoint changes the menu-bar icon immediately, with no restart.
- [ ] The popover shows `via <model> · cloud` under the action grid, and only then.
- [ ] A rewrite against the remote endpoint streams into the result pane, and the word-level diff highlights as it does on-device.
- [ ] Replace still pastes into Slack, and ⌘Z in Slack still restores the original.
- [ ] Switching back to Apple on-device takes effect on the very next action.
- [ ] `codesign -d --entitlements - build/.../Verbaine.app` lists `com.apple.security.network.client` and no `network.server`.
```

- [ ] **Step 8: Build, test, and verify end to end**

Run both `xcodebuild` commands. Expected: build succeeds, every test passes.

Then run the app and work the T3.9 checklist above against a real endpoint. A remote rewrite that fails with a sandbox error means Step 1 did not take — check the entitlement is in the built product, not just the source file.

- [ ] **Step 9: Commit**

```bash
git add Verbaine.entitlements Sources/Verbaine/Resources/PrivacyInfo.xcprivacy \
        Sources/Verbaine/App/VerbaineApp.swift Sources/Verbaine/UI/PopoverView.swift \
        docs/PRD.md docs/TASKS.md docs/TESTING.md CLAUDE.md
git commit -m "feat: show when inference is remote, and allow it to be (T3.9)"
```

---

## Notes for the executor

- **Do not weaken a test to make it pass.** Every expectation here encodes a decision from the spec. If one fails, the source is wrong.
- **No test may open a socket.** The provider is tested through its pure surfaces; the wire format is verified by hand against a real endpoint in Tasks 3 and 4.
- **The key never leaves the Keychain.** If you find yourself putting it in a log line, an error message or a `UserDefaults` write, stop.
- **`docs/TASKS.md` gets the commit hash** on each task's line as it lands, per the repo's convention.
- **One deviation from the spec.** It lists a test for a JSON object split across two network
  chunks. `SSEStream` parses lines rather than bytes, because `URLSession.bytes(for:).lines`
  already reassembles them, so there is no buffering code of ours to test. The remaining SSE tests
  cover everything the spec asked for.
