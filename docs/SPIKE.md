# Phase 0 spike report

**Test Mac:** MacBook Pro, Apple M1 Pro, 16 GB, macOS 27.0 (26A428), Xcode 27.0. Apple Intelligence enabled, Accessibility granted to `Verbaine.app`.
**Date:** 2026-09-18.

Model numbers come from `scripts/spike-measure.swift` (`xcrun swift scripts/spike-measure.swift`), run headless against `SystemLanguageModel.default`. App-level results come from the checklists in `docs/TESTING.md`, run by hand on the same machine.

## Verdict per task

| Task | Result | Note |
|---|---|---|
| T0.2 Foundation Models hello world | **PASS** | `availability = available`, `contextSize = 4096`. Grammar sample 0.93 s; worst action/sample pair measured 4.37 s. |
| T0.3 Selection capture via Accessibility | **PASS** | Notes and Mail return text and non-nil bounds. Slack returns empty, as expected. Clipboard untouched. |
| T0.4 Selection capture via clipboard fallback | **PASS** | Slack and Chrome return the exact selection via ⌘C; string and image clipboards both survive, including on the timeout path. |
| T0.5 Paste-based write-back | **PASS** | Replace works in Slack, Mail and Notes; one ⌘Z restores the original in each; focus-change and app-quit guards abort without pasting. |

No blocking failure. The two load-bearing bets — AX→clipboard fallback and paste-based write-back — both hold on real apps.

## Context window

`contextSize` reads **4096** on this Mac. Measured, not assumed; the code reads it at runtime.

## Token counts — 5 sample messages

| Sample | Shape | Chars | Tokens | Chars/token |
|---|---|---:|---:|---:|
| `slack-short` | one-line Slack ask | 91 | 24 | 3.8 |
| `slack-medium` | Slack incident recap | 312 | 73 | 4.3 |
| `mail-formal` | email draft | 319 | 67 | 4.8 |
| `notes-long` | ~6-paragraph note | 2112 | 410 | 5.2 |
| `one-word` | single misspelled word | 7 | 2 | 3.5 |

≈4–5 chars per token for English prose. A 4096-token window is therefore roughly 18–20 k characters of input *before* the instruction, the wrapper and the output reserve — T1.3 sizes the real budget.

Provisional instruction strings cost 16–31 tokens each (`fixGrammar` 16, `summarize` 20, `shorten` 21, `expand` 21, `changeTone-professional` 22, `improve` 31) — comfortably inside the 120-token cap T1.2 enforces.

## Latency per action

Seconds from `respond(to:)` call to full content, fresh `LanguageModelSession` per call with `prewarm()`, non-streaming.

| Sample (in tok) | fixGrammar | improve | summarize | shorten | tone→prof. | expand |
|---|---:|---:|---:|---:|---:|---:|
| `one-word` (2) | 0.57 | 0.50 | 1.19 | 0.49 | 0.66 | 1.02 |
| `slack-short` (24) | 1.62 | 1.28 | 1.46 | 1.08 | 1.19 | 1.94 |
| `mail-formal` (67) | 2.10 | 2.15 | 1.73 | 1.80 | 2.31 | 2.50 |
| `slack-medium` (73) | 2.18 | 2.16 | 1.87 | 1.96 | 2.51 | 2.98 |
| `notes-long` (410) | 2.32 | 2.55 | 2.21 | 2.29 | 3.30 | 4.37 |

Reading: latency tracks **output** tokens, not input. Input grew 17× from `slack-short` to `notes-long` and cost under a second; `expand`, which emits the most, is the slowest action at every size. Everything a person would type into Slack answers in 1–3 s — fast enough that streaming the result (T1.4) is polish, not a rescue.

## Failure found: long input is silently compressed, not rewritten

`notes-long` is 410 input tokens. Every rewrite action returned ~70–78 output tokens — a quarter of the input. `fixGrammar` on a 6-paragraph note is supposed to return 6 paragraphs; it returned a condensed version instead. Nothing threw: no `contextSizeExceeded`, no guardrail error, just a short answer.

Consequence: token budget alone does not decide when to chunk. The input fits the window by a wide margin (410 ≪ 4096) and the model still declines to reproduce it. So the paragraph-by-paragraph path (T2.2) is not only an over-budget fallback — rewrites need it well below the limit, and T1.3's `fitsInOnePass` must account for output length, not just whether input fits.

Second consequence for T1.4: a result much shorter than the original is a signal worth showing. The word-level diff makes it visible rather than something the user discovers after Replace.

Also worth recording: `summarize` and `expand` on `one-word` ("recieve") produce filler — 26 and 31 tokens out of a 2-token input. T2.4's minimum-length gate should cover the tiny-selection case, not only the huge one.

## AX vs clipboard, by app

| App | Bundle id | Path taken | Notes |
|---|---|---|---|
| Notes | `com.apple.Notes` | Accessibility | Text and bounds; focused-element guard live on write-back. |
| Mail | `com.apple.mail` | Accessibility | Text and bounds in a draft. |
| TextEdit | `com.apple.TextEdit` | Accessibility | Empty selection reports `emptySelection`, no ⌘C posted. |
| Slack | `com.tinyspeck.slackmacgap` | Clipboard | AX exposes a tree but not `kAXSelectedTextAttribute`. On `electronFallbackList`. |
| Chrome | `com.google.Chrome` | Clipboard | Same; web page selections come back exact. |

The fallback list is doing the work it was added for: every Electron/Chromium app tested needs it, and no AppKit app does. Bounds are the cost — the clipboard path has no selection rectangle, so the popover positions at the mouse instead (T1.4).

## Open items carried into Phase 1

- `DebugMenu.swift` is spike scaffolding and gets deleted when T1.4 lands a real popover.
- `scripts/spike-measure.swift` uses provisional instruction strings; T1.2 moves the real ones to `Sources/Verbaine/Model/Prompts.swift`.
- Latency here is non-streaming, whole-response. T1.4 should re-measure time-to-first-token, which is what the user actually perceives.
