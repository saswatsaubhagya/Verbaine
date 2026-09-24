# Bring-your-own-key remote provider — design

Date: 2026-09-18
Status: approved, ready for implementation plan
Tasks: T3.6–T3.9 in `docs/TASKS.md`

## Problem

Verbaine runs every action on Apple's on-device Foundation Model. That model is ~3B parameters with
a 4096-token window, which caps both quality and input size. Users who already pay for a frontier
model want to point Verbaine at it for the actions where the small model falls short, without giving
up on-device as the default.

## Non-goal: reusing an existing subscription

A ChatGPT Plus or Claude Pro subscription grants no API access — no token, no endpoint, no quota.
There is no supported way for a third-party app to make inference calls on the strength of a
consumer chat subscription. Remote inference therefore requires an API key with its own
pay-per-token billing, which the user creates and pastes in. This is stated here so it is not
re-litigated later.

One consequence simplifies the design: every provider worth supporting speaks the OpenAI
`/chat/completions` wire format, either natively (OpenAI, Groq, OpenRouter, Together, Ollama,
LM Studio, vLLM) or through a documented compatibility layer (Anthropic). So this is **one**
provider implementation with a user-supplied base URL, not one per vendor.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| PRD "100% on-device" | Amend; ship in v1 | On-device stays the default and the pitch; the claim becomes conditional on the user's own configuration |
| Token counting for remote | `text.count / 4` estimate against a user-declared context size | Correct tokenizers are per-vendor and per-version; at a 128k window the estimate never changes the single-pass verdict |
| Privacy visibility | Tinted menu-bar icon + `via <model> · cloud` line in the popover | Always visible at the moment of sending, costs no clicks |
| Streaming | Hand-rolled SSE over `URLSession.bytes(for:)` | Keeps the hero flow identical for local and remote; ~50 lines, no dependency |
| Model selection | Free-text field | Works with every endpoint, including the ones with no `/v1/models` route |
| Test connection | Yes | A typo'd key must fail in Settings, not mid-flow with the user's text already captured |

## Architecture

### The seam already exists

`ParagraphRewriter.swift` declares `TextGenerating`, `TokenBudget.swift` declares `TokenCounting`,
and both are already stubbed in tests. `ModelService` is the only conformer today. The change is to
compose them into one protocol and route through a resolver:

```swift
protocol InferenceProvider: TextGenerating, TokenCounting, Sendable {
    var availability: ModelAvailability { get }
    var contextSize: Int { get }
    var isRemote: Bool { get }
    var displayName: String { get }
    func stream(instructions: String, prompt: String) -> AsyncThrowingStream<String, any Error>
}

enum Inference {
    /// Resolved per call, not cached: switching providers in Settings must take effect on the
    /// next action without an app restart.
    static var current: any InferenceProvider { ... }
}
```

`ModelService` conforms as written — `availability`, `contextSize`, `tokenCount`, `respond` and
`stream` already match; `isRemote` is `false` and `displayName` is `"Apple on-device"`.

Callers change mechanically. The concrete-typed convenience initialisers

```swift
init(service: ModelService = .shared)
```

in `TokenBudget`, `TextChunker`, `ParagraphRewriter` and `MapReduceSummarizer` become

```swift
init(service: any InferenceProvider = Inference.current)
```

and the direct `ModelService.shared` references in `PopoverModel`, `CustomAction`,
`ServicesProvider`, `OnboardingModel` and `DebugMenu` become `Inference.current`. One exception:
`OnboardingModel` keeps `ModelService.shared`, because onboarding is specifically about getting
Apple Intelligence turned on and must not be satisfied by a configured remote key.

### Remote provider — `Sources/Verbaine/Model/Remote/`

**`RemoteConfig.swift`** — `struct RemoteConfig: Codable, Sendable` holding `baseURL: URL`,
`model: String`, `contextSize: Int` (default 128_000). Persisted in `UserDefaults` under
`model.remote.*` keys through `Preferences`, alongside `model.provider` (`"apple" | "remote"`).
The API key is *not* in here.

**`APIKeyStore.swift`** — Keychain wrapper over `kSecClassGenericPassword`, service
`in.saswatsaubhagya.verbaine.apikey`, account = the base URL's host, so switching endpoints does not silently
reuse another endpoint's key. `save`, `load`, `delete`. Security.framework only, no dependency. The
key is never written to `UserDefaults`, never logged, and is redacted from every error path.

**`OpenAICompatibleProvider.swift`** — an actor mirroring `ModelService`'s surface.
`POST {baseURL}/chat/completions`, `Authorization: Bearer <key>`, body:

```json
{ "model": "<config.model>",
  "messages": [ {"role": "system", "content": "<instructions>"},
                {"role": "user",   "content": "<prompt>"} ],
  "stream": true }
```

`availability` is `.ready` when a base URL, model and key are all present, otherwise it maps to an
error the user can act on. `contextSize` comes from the config. `tokenCount` returns
`text.count / 4` — marked in the source as a deliberate estimate with its upgrade path.

**`SSEStream.swift`** — parses `data:` lines off `URLSession.bytes(for:)`, decodes
`choices[0].delta.content`, accumulates, and terminates on `data: [DONE]`. It yields **cumulative**
snapshots, matching what `ResponseStream` yields today, so `PopoverModel.streamSinglePass` and the
word-level diff need no change at all. Must survive a JSON object split across byte chunks, blank
keep-alive lines, and a stream that ends without `[DONE]`.

### Errors

`UserFacingError` gains cases mapped from HTTP status and `URLError`:

| Condition | Message intent | Remedy |
| --- | --- | --- |
| 401 / 403 | API key rejected | open Settings |
| 404, or 400 naming the model | Model name not recognised by this endpoint | open Settings |
| 429 | Provider is rate-limiting; try again shortly | dismiss |
| 5xx | Provider had a server error | dismiss |
| `URLError` (offline, DNS, TLS, timeout) | Could not reach the endpoint | dismiss |

`ContextRetry.isContextSizeExceeded` gains a third vocabulary: a 400 whose body names
`context_length_exceeded`. That routes the remote path into the existing halve-and-retry backstop,
so "never truncate silently" holds for remote exactly as it does for local.

### Settings — new "Model" tab

Radio: **Apple on-device** (default) / **Custom endpoint**. When custom is selected: Base URL,
API key (`SecureField`), Model (free text), Context size, and a **Test connection** button that
sends a five-token prompt and reports ok / 401 / 404 / unreachable. A presets popup prefills the
base URL field for OpenAI, Anthropic, OpenRouter, Groq, Ollama and LM Studio — text prefill only,
no per-vendor code path. The tab carries a plain sentence stating that with a custom endpoint the
selected text is sent to that endpoint.

### Privacy surface

- Menu-bar icon renders in a distinct tint whenever `Inference.current.isRemote`.
- The action popover shows `via <model> · cloud` under the action grid on the same condition.
- `Verbaine.entitlements` gains `com.apple.security.network.client`.
- `PrivacyInfo.xcprivacy` gains a data-collection entry for user content sent to a third party,
  conditional on user configuration.
- `docs/PRD.md` amended: goal 3 becomes "On-device by default. Text leaves the Mac only when the
  user configures their own endpoint, and the UI says so whenever it is active." The Network
  permission row and the Privacy posture bullet are updated to match.

## Testing

Unit, no live network anywhere:

- `SSEStream`: happy path, object split across chunks, keep-alive lines, missing `[DONE]`,
  malformed JSON line skipped.
- HTTP status → `UserFacingError` mapping, one case per row of the error table.
- `APIKeyStore` save / load / overwrite / delete round-trip.
- `RemoteConfig` `UserDefaults` round-trip and defaults.
- `TokenBudget` driven by the estimating counter: confirms a 4,000-word selection is single-pass at
  a 128k window and chunking does not fire.
- `Inference.current` returns the Apple provider by default, and the remote provider only when the
  provider preference is remote *and* the config is complete.
- Existing 115 tests stay green after the T3.6 refactor with no behavioural change.

Manual checklist in `docs/TESTING.md`: real key against one endpoint, streaming visible, Replace
still works in Slack, wrong key reports cleanly, offline reports cleanly, switching back to
on-device works without restart.

## Task breakdown

- **T3.6** `InferenceProvider` + `Inference` router; all call sites moved; no behaviour change.
- **T3.7** `RemoteConfig`, `APIKeyStore`, Settings Model tab, Test connection.
- **T3.8** `OpenAICompatibleProvider`, `SSEStream`, error mapping, `ContextRetry` extension.
- **T3.9** Privacy surface: icon tint, popover badge, entitlement, `PrivacyInfo`, PRD amendment.

## Explicitly out of scope

Fetching `/v1/models` into a dropdown. Per-vendor adapters. A real BPE tokenizer. Per-action
provider selection (the provider is global). Streaming or diff changes — both work unmodified.
