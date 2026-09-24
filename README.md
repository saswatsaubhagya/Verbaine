# Verbaine

macOS menu-bar app that rewrites or summarizes text selected in any app, on-device by default via Apple's Foundation Models framework. No network, no account, no cloud — unless you configure your own API endpoint, and the menu bar says so whenever that's active.

Website source: [`site/`](site/) (static HTML, open `site/index.html`).

## Requirements

- Apple Silicon Mac, macOS 26.0 or later
- Xcode 26 or later
- Apple Intelligence enabled (Settings → Apple Intelligence & Siri)
- Accessibility permission granted to Verbaine (Settings → Privacy & Security → Accessibility)

## Installing a release build

Verbaine is signed ad-hoc, not with an Apple Developer certificate, so macOS will refuse to open it on the first launch. To install it:

1. Move `Verbaine.app` to `/Applications`.
2. Double-click it. macOS will say it cannot verify the app is free of malware — this is expected for an app distributed outside the App Store.
3. Open System Settings → Privacy & Security, scroll to the bottom, and click **Open Anyway** next to the message about Verbaine.
4. Launch it again and confirm.

macOS 26 no longer offers the Control-click shortcut for this; the Privacy & Security pane is the only route. Removing the warning entirely requires notarization, which needs a paid Apple Developer Program membership.

One consequence to expect if you use a custom API endpoint: an ad-hoc signature is tied to the exact build, so **updating Verbaine can make macOS treat the new build as a different app and prompt for permission to read your stored API key**. Approving the prompt keeps the key; if the key is not picked up, re-enter it in Settings → Model.

## Build and test

```sh
xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' build
xcodebuild -project Verbaine.xcodeproj -scheme Verbaine -destination 'platform=macOS' test
```

## Layout

| Folder | Contents |
| --- | --- |
| `Sources/Verbaine/App/` | App entry point, menu bar extra |
| `Sources/Verbaine/Capture/` | Selection capture (Accessibility API, clipboard fallback) |
| `Sources/Verbaine/Model/` | `ModelService`, token budget, chunking, prompts |
| `Sources/Verbaine/UI/` | Action popover panel and views |
| `Sources/Verbaine/WriteBack/` | Paste-based replacement into the source app |
| `Sources/Verbaine/Settings/` | Settings window |
| `Tests/VerbaineTests/` | Unit tests |

Target folders are file-system synchronized: adding a file to `Sources/Verbaine/` puts it in the app target automatically, no `.xcodeproj` edit needed.
