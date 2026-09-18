# Claude Code task list — Polish

Execute in order. Each task is one Claude Code session or prompt; commit at the end of every task. Do not start a task until the previous task's **Done when** passes. Reference `PRD.md` for product decisions; do not invent features not listed there.

**Ground rules for every task**

- Swift 6 strict concurrency, SwiftUI + AppKit, Xcode 26, deployment target macOS 26.0.
- No third-party dependencies unless a task names one.
- Every task adds or updates unit tests where logic exists; UI-only tasks add a manual test checklist to `docs/TESTING.md`.
- Never hard-code 4096; always read `SystemLanguageModel.default.contextSize`. It reports 4096 on the current test Mac, but that is a measurement, not a constant.
- All prompts live in `Sources/Polish/Model/Prompts.swift`, one static string per action.
- Run both `xcodebuild` commands from `README.md` (build and test) before declaring a task done.

## Phase 0 — Spike (prove the risky parts first)

**T0.1 Project scaffold** — ✅ done (`1ab6464`)

- Create an Xcode project `Polish`, macOS app, SwiftUI lifecycle, bundle id `com.saswat.polish`.
- Set `LSUIElement = YES` (menu bar only, no Dock icon).
- Add a `MenuBarExtra` with a placeholder menu: "Improve selection", "Settings…", "Quit".
- Folder layout: `App/`, `Capture/`, `Model/`, `UI/`, `WriteBack/`, `Settings/`, `Tests/`.
- Add `.gitignore`, `README.md`, `docs/TESTING.md`.
- Done when: app launches, icon appears in menu bar, Quit works.

**T0.2 Foundation Models hello world** — ✅ done (`cb186ff`, 0.93 s for the sample)

- Add `ModelService` actor wrapping `SystemLanguageModel.default`.
- Implement `availability` check that maps every `SystemLanguageModel.Availability` case to a user-facing enum (`ready`, `intelligenceDisabled`, `modelDownloading`, `unsupportedDevice`).
- Implement `respond(instructions:prompt:) async throws -> String` that creates a fresh `LanguageModelSession` per call and calls `prewarm()`.
- Log `contextSize` and `tokenCount(for:)` for a sample string in debug.
- Done when: a debug menu item sends "Fix grammar: I has a apple" and prints the corrected text to the console in under 3 s on M1.

**T0.3 Selection capture via Accessibility** — ✅ done (`afe39e3`; build + test pass, manual Notes/Mail checklist in `docs/TESTING.md` still to run)

- Add `AccessibilityPermission` helper: check `AXIsProcessTrusted()`, open System Settings pane on request.
- Implement `AXSelectionReader`: get focused element of frontmost app, read `kAXSelectedTextAttribute`, `kAXSelectedTextRangeAttribute`, and bounds via `kAXBoundsForRangeParameterizedAttribute`.
- Return a `Selection` struct: `text`, `bounds: CGRect?`, `appBundleID`, `elementRef`.
- Done when: with Mail or Notes frontmost and text selected, a debug menu item logs the selected text and bounds.

**T0.4 Selection capture via clipboard fallback** — ✅ done (`95e8c4c`; build + test pass, manual Slack/Chrome checklist in `docs/TESTING.md` still to run)

- Implement `ClipboardSelectionReader`: snapshot `NSPasteboard.general` (all types), post ⌘C via `CGEvent`, wait up to 300 ms polling `changeCount`, read string, restore snapshot.
- Implement `SelectionCapture` facade: try AX; if text is empty or app bundle id is in `electronFallbackList` (Slack, Discord, VS Code, Chrome, Arc, Figma), use clipboard method.
- Done when: with Slack desktop frontmost and text selected, debug menu logs the selected text; user's original clipboard is intact afterwards.

**T0.5 Paste-based write-back** — ✅ done (`bb1b2ad`; build + test pass, manual Slack/Mail/Notes checklist in `docs/TESTING.md` still to run)

- Implement `WriteBackService.replace(selection:with:)`: snapshot clipboard, set result string with a transient marker type (`org.nspasteboard.TransientType`), activate source app by bundle id, post ⌘V via `CGEvent`, restore clipboard after 300 ms.
- Guard: before pasting, re-read frontmost app bundle id and focused element; abort with `.focusChanged` error if either differs from capture time.
- Done when: select text in Slack → debug menu "Improve selection" → text replaced in Slack; ⌘Z in Slack restores the original.

**T0.6 Spike report**

- Write `docs/SPIKE.md`: measured latency per action on the test Mac, token counts for 5 sample messages, which apps worked with AX vs clipboard, any failures.
- Done when: file committed and each of T0.2–T0.5 has a pass/fail line.

## Phase 1 — MVP

**T1.1 Global hotkey**

- Implement `HotkeyManager` using Carbon `RegisterEventHotKey` (default ⌃⌥P). Store in `UserDefaults`.
- Hotkey triggers `SelectionCapture` → opens the action popover.
- Done when: hotkey works while Slack, Safari and Mail are frontmost.

**T1.2 Action definitions and prompts**

- Create `Action` enum: `fixGrammar, improve, summarize, shorten, changeTone(Tone), expand`.
- Create `Prompts.swift` with instructions per action, each ≤ 120 tokens, imperative, output-only ("Return only the corrected text, no preamble").
- `Tone` enum: `professional, friendly, direct, apologetic`.
- Unit test: every instruction's `tokenCount` ≤ 120.
- Done when: tests pass.

**T1.3 Token budget service**

- Implement `TokenBudget`: given action + input, compute `fitsInOnePass: Bool` using `contextSize`, instruction tokens, wrapper tokens, output reserve (input×1.3 for rewrites, 400 for summarize/shorten) and 150 margin.
- Expose `maxSinglePassInputTokens(for action:)`.
- Unit tests with stubbed token counts.
- Done when: tests pass.

**T1.4 Action popover UI**

- Non-activating `NSPanel` hosting a SwiftUI view, positioned at selection bounds or mouse location.
- Step 1: action grid (6 actions, tone shows sub-menu). Step 2: two-pane result view, original left, result right, streaming text via `streamResponse`.
- Word-level diff highlighting (implement simple LCS diff in `DiffEngine`, tests included).
- Buttons: Replace (⏎), Copy (⌘C), Retry, close (Esc). Loading state, error state.
- Done when: full flow works in Notes: select → hotkey → Improve → Replace.

**T1.5 Undo buffer and toast**

- `UndoBuffer` keeps (original, result, selection metadata) for 60 s.
- After Replace, show a small toast "Replaced · Undo" for 4 s; clicking it or pressing ⌘Z while popover focused runs write-back with the original.
- Done when: Replace then Undo restores text in Slack and Mail.

**T1.6 Error handling**

- Map `LanguageModelError.contextSizeExceeded`, `GenerationError.guardrailViolation`, model unavailable, focus changed, capture empty to specific user messages in `UserFacingError`.
- Guardrail case offers "Copy original" only.
- Done when: each error can be triggered in a debug menu and shows the right message.

**T1.7 Onboarding**

- First-launch window: 3 steps — what Polish does; enable Apple Intelligence (with availability status live); grant Accessibility (with Test button that reads current selection).
- Done when: fresh install on a clean user account completes onboarding and hotkey works.

**T1.8 Settings window**

- Tabs: General (hotkey, launch at login via `SMAppService`, summary style bullets/paragraph), Apps (Electron fallback list, editable), About.
- Done when: settings persist across relaunch.

**T1.9 TestFlight build**

- App icon, privacy manifest (no tracking, no collection), sandbox entitlements, notarization script `scripts/release.sh`.
- Update `docs/TESTING.md` with the manual checklist for Slack, Mail, Notes, Safari, Chrome.
- Done when: build uploaded to TestFlight.

## Phase 2 — Long text

**T2.1 Chunker**

- `TextChunker` using `NLTokenizer`: split on paragraphs, then sentences, never mid-sentence. Modes: `paragraphs` (for rewrites) and `budgeted(maxTokens:overlapSentences:)` (for summaries).
- Unit tests with long fixtures in `Tests/Fixtures/`.
- Done when: tests pass, no chunk exceeds budget.

**T2.2 Paragraph-by-paragraph rewrite**

- For rewrite actions over budget: run one fresh session per paragraph sequentially, preserve blank-line structure, stitch in order.
- Progress indicator "Part 3 of 8" in popover; Cancel button cancels the `Task`.
- Done when: a 3,000-word document is Fix-grammar'd with paragraphs intact.

**T2.3 Map-reduce summarize**

- Chunks of ~2,500 tokens; each prompt includes previous chunk summary (capped 150 tokens); final session combines summaries; if combined exceeds budget, run a second reduce level.
- Done when: a 5,000-word thread produces a 3-bullet summary with no context error.

**T2.4 Over-budget UX**

- Before running, popover shows estimated token count and "Long text — processing in N parts" when applicable; for > 12,000 tokens, only Fix grammar and Summarize are enabled with a warning.
- Done when: matches PRD strategy table.

**T2.5 Retry on context error**

- On `contextSizeExceeded`, halve the chunk and retry once before surfacing the error.
- Done when: unit test with a stub model that throws once passes.

## Phase 3 — Launch

**T3.1 Custom actions**

- Settings → Custom Actions: name, instruction text (validated ≤ 300 tokens), default button (Replace/Copy), optional hotkey.
- Custom actions appear in the popover grid after built-ins.
- Done when: a saved "Rewrite as release note" action runs from its hotkey.

**T3.2 Per-action hotkeys and silent mode**

- Any action can have a hotkey; when fired, run immediately and Replace without showing the popover unless an error or over-budget condition occurs; show toast.
- Done when: ⌃⌥G fixes grammar and replaces in Slack with no popover.

**T3.3 App-aware tone presets**

- Map bundle id → default tone (Slack → Friendly, Mail → Professional, Jira/Linear → Direct). Editable in Settings → Apps.
- Done when: Change tone preselects the mapped tone per app.

**T3.4 Services menu integration**

- Register `NSServices` entries for Improve and Summarize with `NSStringPboardType`.
- Done when: right-click → Services → Polish: Improve works in TextEdit.

**T3.5 Store readiness**

- App Store screenshots script, listing copy in `docs/STORE.md` emphasizing on-device privacy and cross-app support, review notes explaining Accessibility use.
- Done when: submitted for review.

## Phase 4 — v1.x backlog (one task each, pick by usage data)

- T4.1 Reply drafts action.
- T4.2 Extract action items using `@Generable struct ActionItems { var items: [String] }`.
- T4.3 Explain / simplify action.
- T4.4 Bullets ↔ prose action.
- T4.5 Subject line generator (3 options, `@Generable`).
- T4.6 Clipboard history (24 h, encrypted in app container, toggle in Settings).
- T4.7 Word/phrase alternatives when selection is ≤ 5 words.
- T4.8 Hindi / Hinglish evaluation script with 50 fixture messages; write results to `docs/LANGUAGES.md`.
- T4.9 Optional floating selection button (off by default).
