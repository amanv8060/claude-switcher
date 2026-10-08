# Contributing

Thanks for helping out! Claude Switcher is a small, dependency-free Swift app, so getting started is quick.

## Build and run

```bash
./build.sh            # builds build/Claude Switcher.app (universal)
open "build/Claude Switcher.app"
```

You need macOS 13+ and the Xcode command line tools (`xcode-select --install`). No Xcode project, no packages.

## Where things live

| File | What it does |
| --- | --- |
| `Sources/Views.swift` | The SwiftUI popover |
| `Sources/AppModel.swift` | State and every user action |
| `Sources/AppDelegate.swift` | Menu bar item, popover, settings menu, menu bar icon, screenshot renderer |
| `Sources/ClaudeCode.swift` | Switching the Claude Code CLI login |
| `Sources/ClaudeDesktop.swift` | Switching Claude Desktop profiles |
| `Sources/UsageAPI.swift` | Usage limits and token refresh |
| `Sources/Keychain.swift` | Small wrapper around `/usr/bin/security` |
| `scripts/make-icon.swift` | Draws the app icon |

## Ground rules

- **Never log, print or send tokens anywhere** except Anthropic's own endpoints, and only for the account they belong to.
- **Be conservative with user data.** Only touch the `claudeAiOauth` / `oauthAccount` keys and Claude Desktop's data folder. Back up before writing, and prefer renames to copies or deletes.
- **Keep it dependency-free.** If you're adding a package, open an issue first.
- Match the surrounding style. Small focused PRs are easiest to review.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages and PR
  titles: `feat:`, `fix:`, `docs:`, `refactor:`, `style:`, `ci:`, `chore:`, with an optional scope
  such as `feat(ui):`.

## UI changes

Regenerate the README screenshots (sample data only, nothing real is shown):

```bash
"build/Claude Switcher.app/Contents/MacOS/ClaudeSwitcher" --render-preview docs
```

## Releasing

Bump `VERSION`, update `CHANGELOG.md`, then push a tag:

```bash
git tag v$(cat VERSION) && git push --tags
```

GitHub Actions builds the app and attaches a zip to the release.
