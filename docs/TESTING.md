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
