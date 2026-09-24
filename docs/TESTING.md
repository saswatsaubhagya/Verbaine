# Manual test checklists

Unit-testable logic lives in the test target. This file covers what only a human can check: real apps, real permissions, real selections.

Record the result and the date next to each run. All T0.1–T0.5 checklists below passed on 2026-09-18 (M1 Pro, macOS 27.0).

## T0.1 — Project scaffold

- [x] `xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' build` succeeds.
- [x] Launching `Verbaine.app` shows a wand icon in the menu bar.
- [x] No Dock icon and no app window appear on launch (`LSUIElement`).
- [x] The menu lists "Improve selection", "Settings…", "Quit Verbaine".
- [x] "Settings…" opens the placeholder Settings window.
- [x] "Quit Verbaine" (or ⌘Q with the menu open) terminates the app and removes the menu bar icon.

## T0.2 — Foundation Models hello world

Needs Apple Intelligence enabled (Settings → Apple Intelligence & Siri). Watch the log with
`log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug` while clicking.

- [x] Debug → "Model availability" logs `ready` on a machine with Apple Intelligence on.
- [x] Debug → "Fix grammar sample (T0.2)" logs `contextSize=… tokens=…` for the sample.
- [x] The same item logs `I has a apple -> I have an apple.` (or equivalent correction).
- [x] The logged elapsed time is under 3 s.

## T0.3 — Selection capture via Accessibility

Needs Accessibility permission (System Settings → Privacy & Security → Accessibility → Verbaine).
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

- [x] With permission **not** granted, Debug → "Read AX selection (T0.3)" logs `not trusted`, shows the system prompt and opens the Accessibility pane.
- [x] With permission granted and text selected in Notes, the same item logs `app=com.apple.Notes`, a non-nil `bounds` and the exact selected text.
- [x] Same in Mail (`com.apple.mail`) with text selected in a draft.
- [x] With an app frontmost but nothing selected, it logs `emptySelection` and changes nothing.
- [x] With Slack frontmost and text selected, it logs `emptySelection` or empty text — expected; the clipboard fallback (T0.4) is what covers Electron.
- [x] The user's clipboard is untouched by all of the above.

## T0.4 — Selection capture via clipboard fallback

Needs Accessibility permission (posting ⌘C requires the same trust as reading).
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

Before each run, copy a marker string (e.g. `MARKER-123`) so the clipboard restore is checkable.

- [x] With Slack frontmost and a message selected, Debug → "Capture selection (T0.4)" logs `source=clipboard`, `app=com.tinyspeck.slackmacgap` and the exact selected text.
- [x] Immediately after, ⌘V in any app still pastes `MARKER-123` — the original clipboard survived.
- [x] Same in Chrome (`com.google.Chrome`) with text selected on a web page.
- [x] With Notes frontmost and text selected, the same item logs `source=accessibility` and the clipboard marker is untouched (no ⌘C was posted).
- [x] With Slack frontmost and **nothing** selected, it logs `emptySelection` or `clipboardCopyTimedOut`, and the clipboard marker still pastes.
- [x] Copy an image (not text) as the marker, then capture from Slack: after capture, ⌘V still pastes the image.
- [x] With TextEdit frontmost and nothing selected, it logs `emptySelection` (AX path returned nothing, ⌘C copied nothing) and the clipboard is intact.

## T0.5 — Paste-based write-back

Needs Accessibility permission and Apple Intelligence enabled.
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

Before each run, copy a marker string (e.g. `MARKER-123`) so the clipboard restore is checkable.

- [x] With Slack frontmost and a message with a grammar error selected, Debug → "Improve selection (T0.5)" replaces the selected text in place with the corrected version.
- [x] ⌘Z in Slack immediately after restores the original text (one undo, not several).
- [x] After the replace, ⌘V in any app still pastes `MARKER-123` — the original clipboard survived.
- [x] A clipboard manager (if installed) does not record the rewrite — the transient type was honoured.
- [x] Same in Mail (`com.apple.mail`) with text selected in a draft: replace works and ⌘Z restores.
- [x] Same in Notes (`com.apple.Notes`, AX path, so the focused-element guard is live).
- [x] Select text in Notes, trigger the item, then click into a **different** Notes note (or a different app) while the model is running: the log shows `focusChanged`, nothing is pasted, and the clipboard marker is intact.
- [x] Select text in Slack, then quit Slack while the model is running: the log shows `sourceAppGone` and nothing is pasted.
- [x] With nothing selected anywhere, the item logs a capture error and no paste happens.

## T1.1 — Global hotkey

Needs Accessibility permission. Run the built app (not the Xcode preview) so the hotkey registers.
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

- [ ] With Slack frontmost and text selected, ⌃⌥P logs `hotkey fired` then `captured N chars from com.tinyspeck.slackmacgap`.
- [ ] Same with Safari frontmost (`com.apple.Safari`) and text selected on a page.
- [ ] Same with Mail frontmost (`com.apple.mail`) and text selected in a draft.
- [ ] ⌃⌥P with nothing selected logs `capture failed: emptySelection` and changes nothing.
- [ ] Typing ⌃⌥P inside a text field does not insert a character in the host app (the hotkey swallows it).
- [ ] Menu bar → "Improve selection" does the same as the hotkey.
- [ ] Quit and relaunch: ⌃⌥P still works (the default is read from `UserDefaults` each launch).

## T1.4 — Action popover UI

Needs Accessibility permission and Apple Intelligence enabled. Run the built app.
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

- [ ] Select text in Notes, press ⌃⌥P: the popover appears just below the selection, showing the selected text and a 6-button action grid.
- [ ] Notes stays frontmost (its title bar stays active) and the selection stays highlighted while the popover is open.
- [ ] "Change tone" opens a sub-menu listing Professional, Friendly, Direct, Apologetic.
- [ ] Clicking "Improve" switches to the two-pane view, shows a spinner, and the right pane fills in as the model streams.
- [ ] When streaming ends, changed words are highlighted: removals struck through in red on the left, insertions in green on the right.
- [ ] ⏎ (Replace) replaces the text in Notes and closes the popover; ⌘Z in Notes restores the original.
- [ ] ⌘C copies the result, closes the popover, and ⌘V in any app pastes the rewrite.
- [ ] "Retry" re-runs the same action and the result pane refills.
- [ ] Esc closes the popover and changes nothing in Notes.
- [ ] Trigger the popover again while one is open: only one popover is on screen.
- [ ] Select text in an app that reports no bounds (or in Slack, clipboard path): the popover appears at the mouse location instead.
- [ ] Select text near the bottom-right corner of the screen: the whole popover stays on screen.
- [ ] Click into a different app while the model is running, then press ⏎: the log shows `focusChanged`, nothing is pasted, and the error text appears in the popover.

## T1.5 — Undo buffer and toast

Needs Accessibility permission and Apple Intelligence enabled. Run the built app.
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

- [ ] Select text in Mail, ⌃⌥P → Improve → ⏎: the popover closes and a "Replaced · Undo" capsule appears where the popover was.
- [ ] The toast disappears on its own after ~4 s and changes nothing.
- [ ] Clicking "Undo" while the toast is up restores the original text in Mail and closes the toast.
- [ ] Same in Slack (clipboard capture path): Replace, then Undo restores the original.
- [ ] Pressing ⌘Z while the toast is up does the same as clicking Undo.
- [ ] Esc dismisses the toast without undoing.
- [ ] Replace twice in a row: only one toast is on screen, and Undo takes back the second replace.
- [ ] Click into a different app, then click Undo: the log shows `undo failed: focusChanged` and nothing changes.
- [ ] Leave the toast to expire, then press ⌘Z in Mail itself: the host app's own undo still restores the original.

## T1.6 — Error handling

Run the built debug app. Every message below is reachable from the menu-bar **Debug → Errors (T1.6)**
submenu, which throws the real error type through the same mapping the live failures use.

- [ ] Each entry under Debug → Errors opens one panel with one sentence and at most one action button.
- [ ] "Capture: not trusted" and both write-back permission entries offer **Open Settings**, which opens Privacy & Security → Accessibility.
- [ ] "Model off: Intelligence disabled" offers **Open Settings**, which opens the Apple Intelligence pane.
- [ ] "Capture: empty selection" / "no focused element" offer **Close** only — no Retry.
- [ ] "Model: guardrail violation" (and the macOS 27 twin) offers **Copy original** and nothing else.
- [ ] "Model: context exceeded" says the selection is too long and offers **Retry** — no silently truncated result.
- [ ] "Unknown error" shows the generic sentence, not `The operation couldn’t be completed`.
- [ ] Esc and **Close** both dismiss the error panel and change nothing.
- [ ] Live path: turn Apple Intelligence off in System Settings, select text, ⌃⌥P → pick an action: the popover shows the "Turn on Apple Intelligence" message instead of a framework error.
- [ ] Live path: press ⌃⌥P with nothing selected: the "Select some text first" panel appears at the mouse.
- [ ] Live path: start a rewrite, click into another app, press ⏎: the popover shows the "cursor moved" message with **Copy result**, and clicking it puts the rewrite on the clipboard.

## T1.7 — Onboarding

Fresh install on a clean user account, or Debug → "Reset onboarding flag (T1.7)" then relaunch.
Watch the log with `log stream --predicate 'subsystem == "in.saswatsaubhagya.verbaine"' --level debug`.

- [ ] First launch shows the "Welcome to Verbaine" window centred on screen, on step 1 of 3.
- [ ] Step 1 names ⌃⌥P and says everything runs on this Mac; **Continue** is enabled.
- [ ] With Apple Intelligence **off**, step 2 says so, **Continue** is disabled, and "Open Apple Intelligence settings" opens the right pane.
- [ ] Turn Apple Intelligence on without touching the window: within ~1 s the line flips to a green check and **Continue** enables.
- [ ] With permission **not** granted, step 3 says so, **Test it** is disabled, and "Open Accessibility settings" shows the system prompt and opens the pane.
- [ ] Grant Accessibility without touching the window: within ~1 s the line flips to a green check and **Finish** enables.
- [ ] Select text in Notes, then click **Test it**: Notes stays frontmost, its selection stays highlighted, and the window shows the exact selected text.
- [ ] Same with Slack frontmost (clipboard path): the text comes back and the clipboard marker still pastes afterwards.
- [ ] **Test it** with nothing selected shows "Select some text first…" instead of the captured text.
- [ ] **Back** returns to the previous step with its live status intact.
- [ ] **Finish** closes the window; ⌃⌥P then opens the popover over a selection.
- [ ] Quit and relaunch: onboarding does not appear again.

## T1.8 — Settings window

Open with the menu-bar item → **Settings…** (⌘,).

- [ ] Three tabs: General, Apps, About; the window is a fixed size and does not clip any tab.
- [ ] General shows the current shortcut as symbols (⌃⌥P on a fresh install) and **Reset** is disabled.
- [ ] Click the shortcut button: it reads "Press keys…"; press ⇧⌘K → the button shows ⇧⌘K and ⇧⌘K now opens the popover over a selection while ⌃⌥P no longer does.
- [ ] While recording, the pressed key does not also type into the window or trigger its menu item.
- [ ] Press a bare letter with no ⌃/⌥/⌘: recording ends and the shortcut is unchanged.
- [ ] Press Esc while recording: recording ends and the shortcut is unchanged.
- [ ] Record a combination another app owns (e.g. ⌘Space): "Another app already uses that shortcut." appears and the previous shortcut still fires.
- [ ] **Reset** returns to ⌃⌥P and ⌃⌥P fires again.
- [ ] Set "Summarize as" to Paragraph, then summarize a selection: the result is prose, not "- " bullets. Switch back to Bullet points: bullets again.
- [ ] Toggle **Launch Verbaine at login** on; check System Settings → General → Login Items shows Verbaine; toggle off and it disappears. (Needs the app in /Applications; if it fails, the toggle snaps back and shows the reason.)
- [ ] Apps tab lists the six default bundle IDs.
- [ ] **Add…** → pick an app: its bundle ID appears once. Adding the same app twice leaves one entry.
- [ ] Select an entry → **Remove**: it disappears and **Remove** disables again.
- [ ] Remove `com.tinyspeck.slackmacgap`, then press the hotkey over a Slack selection: capture now fails with "Select some text first" (AX path), proving the list is live. Re-add it and capture works again.
- [ ] **Reset** on the Apps tab restores the six defaults.
- [ ] About shows the name, version and build, and says nothing leaves the Mac.
- [ ] About → **Show onboarding again** opens the onboarding window.
- [ ] **Persistence:** change the shortcut, summary style and the app list, quit Verbaine, relaunch → all three come back as set, and the new shortcut fires without opening Settings first.

## T1.9 — Release build

Build with `scripts/release.sh direct` (Developer ID) or `scripts/release.sh testflight`, then run the
exported app from `/Applications`, not from DerivedData — sandbox and notarization only bite there.

**Artefacts**

- [ ] The app icon is the paper-and-sparkle mark in Finder, the Dock's ⌘Tab-less app list, and About; at 16 pt in a Get Info panel it still reads as two lines plus a sparkle.
- [ ] `plutil -p Verbaine.app/Contents/Info.plist` shows `LSUIElement`, `LSApplicationCategoryType = public.app-category.productivity`, `CFBundleShortVersionString` and a `CFBundleVersion` equal to the commit count.
- [ ] `Verbaine.app/Contents/Resources/PrivacyInfo.xcprivacy` is present and declares no tracking and no collected data.
- [ ] `codesign -dv --entitlements - Verbaine.app` shows hardened runtime, the expected identity, and `com.apple.security.app-sandbox` on the Release build.
- [ ] `spctl --assess --type execute --verbose Verbaine.app` says "accepted / Notarized Developer ID" (direct build).
- [ ] Nothing in the bundle links a networking stack: `otool -L Verbaine.app/Contents/MacOS/Verbaine | grep -i -e network -e cfnetwork` is empty.
- [ ] Little Snitch (or `nettop`) records zero outbound connections across a full session of the checks below.

**Sandboxed hero flow** — the point of the TestFlight build is to prove Accessibility works from inside the sandbox. Grant Accessibility to the exported app first (System Settings → Privacy & Security → Accessibility).

For each app: select one sentence with a deliberate typo, press ⌃⌥P, run **Fix grammar**, click **Replace**, then ⌘Z in the host app.

- [ ] Notes (AX path) — capture, replace and the host app's own undo all work.
- [ ] Mail, composing a new message (AX path) — same.
- [ ] Safari, a textarea (AX path) — same.
- [ ] Slack message box (clipboard path) — same, and the clipboard's previous contents still paste afterwards.
- [ ] Chrome, a Google Docs or Gmail compose field (clipboard path) — same.
- [ ] In each app: **Copy** puts the result on the clipboard and the selection is untouched.
- [ ] If any capture fails with an AX error in the sandboxed build, record which app and stop — the sandbox blocks the hero flow and distribution has to move to notarized direct download (PRD "Sandbox").

**Upload**

- [ ] `scripts/release.sh testflight` uploads without validation errors (no missing icon size, no disallowed entitlement, unique build number).
- [ ] The build appears in App Store Connect → TestFlight, finishes processing, and is installable by an external tester on a clean Apple Silicon Mac with Apple Intelligence on.

## T2.2 Long rewrites — manual

Needs the real model: the unit tests stub it, so paragraph fidelity over a long document is only provable on device. Use a 3,000-word document (the one in `Tests/Fixtures/long-document.txt`, repeated until it is that long, pasted into Notes).

- [ ] Select the whole document, ⌃⌥P, **Fix grammar** — the footer shows a spinner and "Part 1 of N", counting up to N.
- [ ] The result pane grows a paragraph at a time rather than appearing all at once at the end.
- [ ] The finished result has the same number of paragraphs as the original, in the same order, separated by single blank lines — no paragraph merged, dropped or duplicated.
- [ ] **Cancel** part-way through stops the run within one part and returns to the action grid; nothing is written back.
- [ ] **Replace** writes the whole stitched result, and ⌘Z in Notes undoes it in one step.
- [ ] A short selection still streams token by token with no "Part" label — the single-pass path is unchanged.

## T2.3 Map-reduce summarize — manual

Needs the real model: the unit tests stub it, so summary quality over a long thread is only provable on device. Use a 5,000-word thread (`Tests/Fixtures/chat-thread.txt`, repeated until it is that long, pasted into Notes).

- [ ] Select the whole thread, ⌃⌥P, **Summarize** — the footer shows "Part 1 of N", counting up to N, with no context-size error at any point.
- [ ] The final result is three bullets (or one short paragraph, per Settings → Summary style), not a wall of per-chunk summaries.
- [ ] The summary mentions things from the start, middle and end of the thread — the carried-forward context is doing its job.
- [ ] **Cancel** part-way through stops within one part and returns to the action grid.
- [ ] **Copy** puts the summary on the clipboard; the original thread in Notes is untouched.
- [ ] A short selection still streams token by token with no "Part" label — the single-pass path is unchanged.

## T3.4 Services menu — manual

The Services menu is a system feature: it reads `NSServices` out of the installed app's bundle, so
nothing here is provable from a unit test. Build and run Verbaine once first (the services cache only
learns about a new entry after the app has launched from its built location); if the items do not
appear, run `/System/Library/CoreServices/pbs -flush` and log out and back in.

- [ ] TextEdit: type a sentence with a clumsy phrasing, select it, right-click → **Services** — "Verbaine: Improve" and "Verbaine: Summarize" both appear.
- [ ] **Verbaine: Improve** replaces the selection in place with the rewritten text; ⌘Z in TextEdit undoes it in one step.
- [ ] **Verbaine: Summarize** on a few paragraphs replaces them with the summary.
- [ ] The same two items appear in Mail and in Safari (in an editable field), and Improve replaces there too.
- [ ] With nothing selected the items are greyed out; with a selection of whitespace only, the system beep/alert says "Select some text first."
- [ ] A very long selection (the 3,000-word document from T2.2) fails with the over-long message rather than hanging or silently truncating — Services runs single-pass only.
- [ ] While a Services action runs, the app's own ⌃⌥P popover still opens afterwards — nothing is left wedged.

## T3.1 Custom actions — manual

The store, the prompt composition and the validation rules are unit-tested (`CustomActionTests`);
what only the running app proves is the Settings editor, the grid and the global shortcut.

- [ ] Settings → **Actions** → **Add** creates "New action"; name it "Rewrite as release note", instruction "Rewrite the user's text as a one-paragraph release note for end users.", default button **Copy**.
- [ ] Paste an instruction longer than 300 tokens (~1,300 characters) — the editor shows "That instruction is N tokens; the limit is 300." Shorten it and the message clears.
- [ ] Clearing the name shows "Give the action a name."; clearing the instruction shows "Write what the action should do."
- [ ] **Shortcut** → record ⌃⌥R; the list row shows "⌃⌥R". **Clear** removes it and the row shows no shortcut.
- [ ] Select text in Notes, ⌃⌥P — "Rewrite as release note" appears in the grid after **Expand**; running it returns a release note.
- [ ] With that action's result on screen, ⏎ copies (the action's default button) rather than replacing; **Replace** still works from the mouse.
- [ ] Quit and relaunch Verbaine: the action is still there, with its shortcut.
- [ ] Select text in Slack and press ⌃⌥R — the action runs and replaces with no popover, the toast confirms it. (T3.1 done-when, silent since T3.2.)
- [ ] Give a second custom action a different shortcut; both fire their own action. Give one a shortcut already owned by another app — Settings says the combination is taken and the old one is kept.
- [ ] **Remove** deletes the action; its shortcut stops firing without a relaunch.
- [ ] A 15,000-token selection greys out the custom action along with Improve/Shorten/Tone/Expand.

## T3.2 Per-action hotkeys and silent mode — manual

The store, the id round-trip and the silent-run gate are unit-tested (`PreferencesTests`,
`SizeEstimateTests`); what only the running app proves is the shortcut firing end to end with no
window on screen.

- [ ] Settings → **Actions** — the built-in actions are listed above the custom ones, **Fix grammar** already showing "⌃⌥G".
- [ ] Select a sentence with a typo in Slack and press ⌃⌥G — no popover appears at any point, the selection is replaced with the corrected text, and the "Replaced · Undo" toast shows. (T3.2 done-when.)
- [ ] ⌘Z (or the toast's **Undo**) puts the original sentence back in one step.
- [ ] Record ⌃⌥I for **Improve** and ⌃⌥K for **Summarize**; both fire silently on a short selection. **Clear** on **Fix grammar** stops ⌃⌥G firing without a relaunch.
- [ ] Record a combination another app owns — Settings says it is taken and keeps the previous one.
- [ ] Select several long paragraphs (the 3,000-word document from T2.2) and press ⌃⌥G — the popover *does* open, running in parts, because the selection needs more than one pass.
- [ ] Select 15,000 tokens and press ⌃⌥I — the popover opens instead of replacing; Improve is not offered at that length.
- [ ] Turn Apple Intelligence off and press ⌃⌥G — the popover opens with the "turn Apple Intelligence on" message instead of replacing silently.
- [ ] With nothing selected, ⌃⌥G shows the empty-capture message rather than doing nothing.
- [ ] Click away to another app between pressing ⌃⌥G and the replace landing — the focus-changed message appears and nothing is pasted into the wrong app.
- [ ] Quit and relaunch: the recorded shortcuts still fire.

## T3.7 — Model settings

- [ ] Settings → Model defaults to "Apple on-device" on a fresh install.
- [ ] Picking "Custom endpoint" reveals Base URL, API key, Model and Context size.
- [ ] Choosing a preset fills the Base URL field and leaves the other fields alone.
- [ ] Typed values survive closing and reopening Settings.
- [ ] The API key field is masked, and the key does not appear in `defaults read in.saswatsaubhagya.verbaine`.
- [ ] Switching back to "Apple on-device" hides the fields but keeps the stored values.

## T3.9 — Remote visibility

- [ ] With Apple on-device selected, the menu-bar icon is the outline wand and the popover shows no badge.
- [ ] Switching to a configured custom endpoint changes the menu-bar icon immediately, with no restart.
- [ ] The popover shows `via <model> · cloud` under the action grid, and only then.
- [ ] A rewrite against the remote endpoint streams into the result pane, and the word-level diff highlights as it does on-device.
- [ ] Replace still pastes into Slack, and ⌘Z in Slack still restores the original.
- [ ] Switching back to Apple on-device takes effect on the very next action.
- [ ] `codesign -d --entitlements - build/.../Verbaine.app` lists `com.apple.security.network.client` and no `network.server`.
- [ ] A custom endpoint whose base URL redirects to a different host is refused rather than followed: the request fails with the "check the base URL in Settings" message, and the API key is not sent onward.

## Final review fix wave (M1–M5)

- [ ] Point the endpoint at a local model with a small output cap (llama.cpp / Ollama `num_predict`), run Improve on two paragraphs: the popover shows the "stopped at its own output limit" message with an Open Settings button, not a finished-looking cut-off result, and Replace is not offered.
- [ ] Kill the endpoint process part-way through a streaming answer: the popover shows the "closed the connection before it finished answering" message rather than committing the fragment.
- [ ] Settings → Model: type `128` in Context size and tab out — the field snaps to 851, and the caption under it says so.
- [ ] With that floored value, Summarize still runs normally instead of producing a blank result.

## Unsigned distribution (ad-hoc signing)

- [ ] A zipped Release build, copied to a Mac that has never seen the project, is blocked on first launch and opens after System Settings → Privacy & Security → **Open Anyway**.
- [ ] With a custom endpoint configured and its API key saved, quitting and relaunching the *same* build keeps the key — Settings → Model still shows it filled in, and an action runs without re-entering it.
- [ ] After replacing the app with a **newly built** copy, check whether the stored API key still works. An ad-hoc signature is tied to the exact build, so macOS may prompt for Keychain access or fail to read the key. Record which happens: a prompt the user can approve is acceptable, silently losing the key is not.
- [ ] `codesign -dv Verbaine.app` reports `Signature=adhoc` and `TeamIdentifier=not set`, and `codesign -d --entitlements - Verbaine.app` still lists `com.apple.security.app-sandbox` and `com.apple.security.network.client`.

## Design parity — the board (`docs/DESIGN.md`)

Run with the board open beside the app, in light **and** dark appearance (System Settings →
Appearance), on a 2× display.

**Popover, step 1 (board row 1)**

- [ ] Panel is 320 pt wide, corner radius 14, glass fill with a hairline edge and a soft shadow — no square title bar.
- [ ] Six tiles, 94 × 62 in a 3 × 2 grid: glyph over an 11 pt medium label, faint fill at rest, darker on hover.
- [ ] Keys 1–6 run the matching tile; the footer reads "1–6 pick · esc close" with an `esc` chip top-right.
- [ ] Press 5 (Change tone): the tile turns accent-tinted, a tone row opens in place, the panel grows downward with its top-left corner unmoved, and the footer switches to "1–4 tone · esc back".
- [ ] Keys 1–4 now pick a tone; Esc closes the sub-row without closing the popover; Esc again closes the popover.
- [ ] Size line reads "142 words · fits in one pass", or "… · long text, N parts" over the single-pass limit.
- [ ] Over 12,000 tokens only Fix grammar and Summarize are enabled; the rest are dimmed and the amber warning line is present.
- [ ] Custom actions appear as pills under a "YOURS" header.

**Result (board row 2)**

- [ ] Panel grows to 560 pt in place; the top-left corner does not move.
- [ ] Header: action title, an accent "On-device" chip (or "<endpoint> · cloud" when a remote endpoint is configured).
- [ ] Two panes under 9.5 pt uppercase "ORIGINAL"/"RESULT" headers, each scrolling on its own, capped at 400 pt total.
- [ ] Unchanged words are 45% ink; removals are struck through in red on a faint red field; additions sit on a green field.
- [ ] Footer reads "142 → 38 words"; Retry, Copy ⌘C and Replace ⏎ are present, with ⏎ on the action's default button.
- [ ] Change tone result shows the four tones in the header; clicking one re-runs against the original without reopening.

**Long text (board row 3)**

- [ ] While parts run: "Part 3 of 8" over a full-bleed 2 pt track whose accent fill advances per part.
- [ ] Only Cancel shows while running — Replace and Copy appear when the last part lands.

**Errors (board row 4)**

- [ ] A failure shows a bold heading, the sentence under it, an `esc` chip, and one remedy button ("Not now" instead of Close when the remedy opens System Settings).

**Placement (board row 4, placement rule)**

- [ ] Popover sits 8 pt below the selection, left edges aligned.
- [ ] With the selection near the bottom of the screen (less than 400 pt of room below), the popover flips above the selection instead of being squashed.

**Undo toast (board row 5)**

- [ ] 30 pt pill, fully rounded, glass, "Replaced" with an accent "Undo ⌘Z".
- [ ] A hairline countdown shrinks along the bottom edge and the toast disappears at 4 s.
- [ ] Hovering the toast pauses the countdown; moving away resumes it.

**Menu bar (board rows 3 and 7)**

- [ ] The menu-bar mark is the two-line-plus-sparkle template image: black in light mode, white in dark, white while the menu is open.
- [ ] The dropdown lists all six actions, then custom actions, then Settings… and Quit Verbaine.
- [ ] With a remote endpoint configured, the mark changes to a cloud.

**Onboarding (board row 5/7)** — Settings → About → Reset onboarding.

- [ ] Window is 520 × 420; headline is 22 pt semibold over a 13 pt subtitle.
- [ ] Step 1 shows the three numbered cards (Select / Pick an action / Replaced) and the "Nothing leaves your Mac" line.
- [ ] Steps 2 and 3 show a status card with a green check when satisfied, amber when not, and the footer reads "Step n of 3" with Back / Continue (the last button reads "Start using Verbaine").

**Settings (board row 6)**

- [ ] Window is 640 × 430; tabs read General, Actions, Apps, Model, About.
- [ ] General: right-aligned labels "Verbaine shortcut:", "Startup:", "Summary style:" with a segmented Bullets/Paragraph control.
- [ ] Actions: a table with Action / Default button / Hotkey columns, built-ins first, then a "CUSTOM" section; double-clicking a custom action opens the edit sheet.
- [ ] Apps: "DEFAULT TONE PER APP" over the tone list, "USING CLIPBOARD FALLBACK" over the bundle-ID list, with the explanation line underneath.
- [ ] About: app icon, name, version, "macOS 26 or later · Apple silicon", and Reset onboarding.
