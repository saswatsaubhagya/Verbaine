# Design reference

Source: claude.ai design project "Verbaine macOS grammar app" (`ed7b1c70-ddfe-4c1e-9095-c22dc10ce104`), board `Verbaine UI Board.dc.html`. A copy is committed at [`docs/design/Verbaine-UI-Board.html`](design/Verbaine-UI-Board.html) — open it in a browser to see every state rendered. Target look: macOS 26 Tahoe, Liquid Glass, light + dark.

Re-pull with the `DesignSync` tool (`/design-login` first) if the board changes. Do not hand-edit the committed copy.

## Boards and the task that consumes each

| Row | Screens | Task |
| --- | --- | --- |
| 1 | Action popover step 1, light + dark, tone sub-row open | T1.4 |
| 2 | Result view — streaming Improve; Change tone with picker | T1.4 |
| 3 | Long-text progress, undo toast, placement rule, menu-bar dropdown | T1.5, T2.2, T2.4 |
| 4 | Error and empty states | T1.6 |
| 5 | Onboarding, 520 × 420, three steps | T1.7 |
| 6 | Settings, 640 × 430, tabbed | T1.8 |
| 7 | App icon | T1.9 |
| 8 | Components sheet — the token source below | all UI tasks |

The menu-bar dropdown board shows clipboard history, which is T4.6 and **not** in v1. Ignore that part of row 3 until then.

## Colour

| Token | Light | Dark |
| --- | --- | --- |
| Accent | `#007AFF` | `#0A84FF` |
| Glass fill | `#F7F7F9` 76–80% | `#28282B` 70–72% |
| Ready / added text | `#34C759` | `#30D158` |
| Warning | `#FF9F0A` | `#FF9F0A` |
| Removed strike | `#FF453A` | `#FF6961` |
| Ink (primary/secondary/tertiary/quaternary) | black 85 / 55 / 40 / 34% | white 92 / 55 / 42 / 35% |
| Hairline | black 9–10% | white 10–14% |
| Selection | accent 22% | accent 36% |

Glass surfaces: backdrop blur 30, saturation 180%.

## Geometry

- Radii: 14 popover · 13 window · 10 tile · 8 button · 7 field · 6 menu item · full pill (toast)
- Spacing scale: 4 6 8 9 12 14 16 20. Popover padding 12; window padding 24–32.
- Widths: 320 popover step 1 · 560 result · 262 menu · 520 × 420 onboarding · 640 × 430 settings
- Popover max height 400; each pane scrolls internally.

## Type

| Face / size | Use |
| --- | --- |
| SF Pro Display 22 semibold | Onboarding headline |
| SF Pro 15 semibold | Window title |
| SF Pro 13 regular | Body, settings labels |
| SF Pro 12.5 regular | Menu items |
| SF Pro 12 regular | Result and original panes |
| SF Pro 11 medium | Action tile labels |
| SF Pro 10.5 regular | Footer meta |
| SF Pro 9.5 uppercase, +6% tracking | Pane headers |
| SF Mono 10–12 | Keyboard hints, recorded shortcuts |

## Components

**Action tile** — 94 × 62, radius 10, padding 9 9 8. Icon 19 at stroke 1.7, gap 6 to an 11/13.75 medium label.

| State | Fill | Border |
| --- | --- | --- |
| Rest | white 55% | black 7% |
| Hover | black 5% | — |
| Selected | accent 13% | accent 30% |
| Pressed | accent 22% | — |
| Focus | — | 2 px accent outline, offset 2 |

**Diff highlights** (T1.4 `DiffEngine`) — word-level, radius 3, padding 0 2.

- Added: `#30D158` at 20% light / 26% dark
- Removed: strikethrough `#FF453A` 60% on `#FF453A` 8% light; `#FF6961` 70% on `#FF453A` 14% dark
- Unchanged original ink: black 45% light / white 45% dark

**Undo toast** (T1.5) — height 30, radius 15, padding 0 6 0 12, gap 8. Glass `#F7F7F9` 80% light / `#2C2C2E` 82% dark, shadow 0 8 24 black 20% (40% dark). Label 12 regular, "Undo" 12 medium accent, "⌘Z" in SF Mono. Lives 4 s with a hairline countdown that pauses on hover.

**Progress row** (T2.2, T2.4) — full-bleed 2 px track, black 10% light / white 14% dark, accent fill that advances one step per completed part. Title 12 semibold, counter 10.5 regular at black 45%. Copy reads "Part 3 of 8".

## In code

`Sources/Verbaine/UI/DesignTokens.swift` is the single place these numbers live — `Tokens.Radius`,
`Tokens.Space`, `Tokens.Size`, `Tokens.Ink`, `Tokens.Palette`, `Tokens.Face`. Views read tokens;
no view hard-codes a hex value or a point size. `View.glassSurface(cornerRadius:)` (in
`PopoverPanel.swift`) draws the blurred fill, hairline edge and shadow the popover, toast and
error pane share. `docs/TESTING.md` → "Design parity" is the checklist that proves a build
matches this file.

## Where the code deviates, and why

- **Settings has a fifth tab, Model.** Bring-your-own-endpoint (T3.6–T3.9) landed after the board was drawn. It sits between Apps and Model's neighbours rather than replacing a board tab.
- **Built-in actions show Replace in the Actions table's "Default button" column.** The board shows Summarize finishing on Copy, but only custom actions carry a per-action default button today; making it editable for built-ins is a preference change, not a design one.
- **Menu-bar shortcuts are shown as a help tag, not a right-aligned column.** A SwiftUI `MenuBarExtra` cannot draw the column; matching the board needs a hand-built `NSMenu`.
- **Not built at all:** "Menu-bar shortcut" and "Show icon in menu bar only when active" (General), and the clipboard history in the menu (T4.6, already excluded from v1 above). These are features the board drew, not styling.
