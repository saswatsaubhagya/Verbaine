# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

T0.1–T0.3 done: menu-bar app scaffolded, `ModelService` talks to the on-device model (measured 0.93 s for a 5-token grammar fix), `AXSelectionReader` reads the frontmost app's selection and bounds. Next task is T0.4 in `docs/TASKS.md`.

## Product

**Polish** — macOS menu-bar app that rewrites/summarizes text selected in *any* app (Slack, Mail, Chrome, Notes) using Apple's on-device Foundation Models. No network, no account, no cloud.

## Working method

`docs/TASKS.md` is the execution plan: tasks run in order, one session per task, commit at the end of each. Do not start a task until the previous task's **Done when** passes. `docs/PRD.md` holds product decisions — do not invent features it does not list.

## Build & test

Xcode 26, macOS 26.4 deployment target, Apple Silicon only. (26.4, not 26.0: `SystemLanguageModel.tokenCount(for:)` is 26.4+, and the architecture depends on measuring rather than estimating tokens.) There is no SwiftPM package — the `.xcodeproj` is the build system:

```sh
xcodebuild -project Polish.xcodeproj -scheme Polish -destination 'platform=macOS' build
xcodebuild -project Polish.xcodeproj -scheme Polish -destination 'platform=macOS' test
```

Both must pass before a task is done. Target folders are file-system synchronized, so a new file under `Sources/Polish/` joins the app target with no `.xcodeproj` edit. Keep Swift file basenames unique across the target — duplicates collide on `.stringsdata` output and fail the build. Runtime needs Apple Intelligence enabled and Accessibility permission granted to the app.

## Non-negotiable constraints

- Swift 6 strict concurrency, SwiftUI + AppKit. No third-party dependencies unless a task explicitly names one.
- Never hard-code the 4096-token window. Read `SystemLanguageModel.default.contextSize` and measure with `tokenCount(for:)` before every model call.
- All prompts live in `Sources/Polish/Model/Prompts.swift`, one static string per action, each ≤120 tokens.
- One fresh `LanguageModelSession` per action — no history carried between calls.
- UI-only tasks add a manual checklist to `docs/TESTING.md`; tasks with logic add unit tests.
- The remote API key lives in the Keychain only, keyed by endpoint host. Never in `UserDefaults`, never in a log line, never in a user-facing message.

## Architecture (four layers)

1. **Capture** (`Capture/`) — `SelectionCapture` facade tries the Accessibility API (`kAXSelectedTextAttribute`) first, falls back to simulated ⌘C + pasteboard read for Electron/Chromium apps (Slack, Discord, VS Code, Chrome, Arc, Figma — an editable list). The clipboard method must snapshot and restore the user's clipboard.
2. **Model** (`Model/`) — `InferenceProvider` is the seam: `ModelService` (actor over `SystemLanguageModel.default`, the default) and `OpenAICompatibleProvider` (`Model/Remote/`, the user's own endpoint) both conform, and `Inference.current` resolves one per call from `Preferences`. `TokenBudget` decides single-pass vs chunked; `TextChunker` (NLTokenizer) splits on paragraph then sentence boundaries, never mid-sentence. Rewrites go paragraph-by-paragraph; summaries use map-reduce with the previous chunk's summary carried forward. Remote token counts are a chars/4 estimate against a user-declared window — exact counting only exists for the on-device model.
3. **UI** (`UI/`) — non-activating `NSPanel` hosting SwiftUI, positioned at the selection's AX bounds. Streaming result with word-level diff against the original.
4. **Write-back** (`WriteBack/`) — Replace works by pasting, not `AXValue` writes: put result on the pasteboard (transient type), re-activate the source app, post ⌘V via `CGEvent`, restore clipboard after ~300 ms. This is what makes Replace work in Slack/browsers and keeps the host app's ⌘Z intact. Before pasting, re-verify frontmost app and focused element match capture time; abort otherwise.

Paste-based write-back and the AX→clipboard fallback are the two load-bearing decisions — changing either breaks the hero flow (PRD "Technical architecture").

## Error mapping

`LanguageModelError.contextSizeExceeded` (halve chunk, retry once), `GenerationError.guardrailViolation` (offer Copy-original only), model unavailable, focus changed, empty capture — all map to specific messages in `UserFacingError`. Never truncate silently.
