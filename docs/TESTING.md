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
