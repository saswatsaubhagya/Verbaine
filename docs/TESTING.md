# Manual test checklists

Unit-testable logic lives in the test target. This file covers what only a human can check: real apps, real permissions, real selections.

Record the result and the date next to each run.

## T0.1 — Project scaffold

- [ ] `xcodebuild -project Polish.xcodeproj -scheme Polish -destination 'platform=macOS' build` succeeds.
- [ ] Launching `Polish.app` shows a wand icon in the menu bar.
- [ ] No Dock icon and no app window appear on launch (`LSUIElement`).
- [ ] The menu lists "Improve selection", "Settings…", "Quit Polish".
- [ ] "Settings…" opens the placeholder Settings window.
- [ ] "Quit Polish" (or ⌘Q with the menu open) terminates the app and removes the menu bar icon.

## T0.2 — Foundation Models hello world

Needs Apple Intelligence enabled (Settings → Apple Intelligence & Siri). Watch the log with
`log stream --predicate 'subsystem == "com.saswat.polish"' --level debug` while clicking.

- [ ] Debug → "Model availability" logs `ready` on a machine with Apple Intelligence on.
- [ ] Debug → "Fix grammar sample (T0.2)" logs `contextSize=… tokens=…` for the sample.
- [ ] The same item logs `I has a apple -> I have an apple.` (or equivalent correction).
- [ ] The logged elapsed time is under 3 s.

## T0.3 — Selection capture via Accessibility

Needs Accessibility permission (System Settings → Privacy & Security → Accessibility → Polish).
Watch the log with `log stream --predicate 'subsystem == "com.saswat.polish"' --level debug`.

- [ ] With permission **not** granted, Debug → "Read AX selection (T0.3)" logs `not trusted`, shows the system prompt and opens the Accessibility pane.
- [ ] With permission granted and text selected in Notes, the same item logs `app=com.apple.Notes`, a non-nil `bounds` and the exact selected text.
- [ ] Same in Mail (`com.apple.mail`) with text selected in a draft.
- [ ] With an app frontmost but nothing selected, it logs `emptySelection` and changes nothing.
- [ ] With Slack frontmost and text selected, it logs `emptySelection` or empty text — expected; the clipboard fallback (T0.4) is what covers Electron.
- [ ] The user's clipboard is untouched by all of the above.

## T0.4 — Selection capture via clipboard fallback

Needs Accessibility permission (posting ⌘C requires the same trust as reading).
Watch the log with `log stream --predicate 'subsystem == "com.saswat.polish"' --level debug`.

Before each run, copy a marker string (e.g. `MARKER-123`) so the clipboard restore is checkable.

- [ ] With Slack frontmost and a message selected, Debug → "Capture selection (T0.4)" logs `source=clipboard`, `app=com.tinyspeck.slackmacgap` and the exact selected text.
- [ ] Immediately after, ⌘V in any app still pastes `MARKER-123` — the original clipboard survived.
- [ ] Same in Chrome (`com.google.Chrome`) with text selected on a web page.
- [ ] With Notes frontmost and text selected, the same item logs `source=accessibility` and the clipboard marker is untouched (no ⌘C was posted).
- [ ] With Slack frontmost and **nothing** selected, it logs `emptySelection` or `clipboardCopyTimedOut`, and the clipboard marker still pastes.
- [ ] Copy an image (not text) as the marker, then capture from Slack: after capture, ⌘V still pastes the image.
- [ ] With TextEdit frontmost and nothing selected, it logs `emptySelection` (AX path returned nothing, ⌘C copied nothing) and the clipboard is intact.

## T0.5 — Paste-based write-back

Needs Accessibility permission and Apple Intelligence enabled.
Watch the log with `log stream --predicate 'subsystem == "com.saswat.polish"' --level debug`.

Before each run, copy a marker string (e.g. `MARKER-123`) so the clipboard restore is checkable.

- [ ] With Slack frontmost and a message with a grammar error selected, Debug → "Improve selection (T0.5)" replaces the selected text in place with the corrected version.
- [ ] ⌘Z in Slack immediately after restores the original text (one undo, not several).
- [ ] After the replace, ⌘V in any app still pastes `MARKER-123` — the original clipboard survived.
- [ ] A clipboard manager (if installed) does not record the rewrite — the transient type was honoured.
- [ ] Same in Mail (`com.apple.mail`) with text selected in a draft: replace works and ⌘Z restores.
- [ ] Same in Notes (`com.apple.Notes`, AX path, so the focused-element guard is live).
- [ ] Select text in Notes, trigger the item, then click into a **different** Notes note (or a different app) while the model is running: the log shows `focusChanged`, nothing is pasted, and the clipboard marker is intact.
- [ ] Select text in Slack, then quit Slack while the model is running: the log shows `sourceAppGone` and nothing is pasted.
- [ ] With nothing selected anywhere, the item logs a capture error and no paste happens.
