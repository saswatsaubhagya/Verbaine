# Polish

macOS menu-bar app that rewrites or summarizes text selected in any app, fully on-device via Apple's Foundation Models framework. No network, no account, no cloud.

- Product spec: [docs/PRD.md](docs/PRD.md)
- Build plan: [docs/TASKS.md](docs/TASKS.md)
- Manual test checklists: [docs/TESTING.md](docs/TESTING.md)

## Requirements

- Apple Silicon Mac, macOS 26.0 or later
- Xcode 26 or later
- Apple Intelligence enabled (Settings → Apple Intelligence & Siri)
- Accessibility permission granted to Polish (Settings → Privacy & Security → Accessibility)

## Build and test

```sh
xcodebuild -project Polish.xcodeproj -scheme Polish -destination 'platform=macOS' build
xcodebuild -project Polish.xcodeproj -scheme Polish -destination 'platform=macOS' test
```

## Layout

| Folder | Contents |
| --- | --- |
| `Sources/Polish/App/` | App entry point, menu bar extra |
| `Sources/Polish/Capture/` | Selection capture (Accessibility API, clipboard fallback) |
| `Sources/Polish/Model/` | `ModelService`, token budget, chunking, prompts |
| `Sources/Polish/UI/` | Action popover panel and views |
| `Sources/Polish/WriteBack/` | Paste-based replacement into the source app |
| `Sources/Polish/Settings/` | Settings window |
| `Tests/PolishTests/` | Unit tests |

Target folders are file-system synchronized: adding a file to `Sources/Polish/` puts it in the app target automatically, no `.xcodeproj` edit needed.
