<p align="center">
  <img src="docs/logo.png" width="112" alt="">
</p>

<h1 align="center">Claude Switcher</h1>

<p align="center">
  A macOS menu bar app for switching between Claude accounts and checking their usage limits.
</p>

<p align="center">
  <a href="https://github.com/amanv8060/claude-switcher/actions/workflows/ci.yml"><img src="https://github.com/amanv8060/claude-switcher/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-555" alt="macOS 13+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555" alt="MIT license"></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="600" alt="The Claude Switcher popover: the current account with session and weekly usage, a suggestion to switch to the account with more room, and a list of other accounts">
  </picture>
</p>

## What it does

- Switches the Claude Code CLI and the Claude Desktop app (including its Code tab) to the same
  account in one click.
- Shows session and weekly limits for every saved account, with reset times. Opus and Sonnet
  limits appear too, if your plan has them.
- Suggests switching when another account has noticeably more room left.
- Shows the current account and its session usage in the menu bar.
- Optionally shows the same Claude Desktop Code sessions under every account (gear icon →
  **Share Code sessions across accounts**).

Shortcuts: <kbd>⌘1</kbd>–<kbd>⌘9</kbd> switch accounts while the popover is open. Right-click an
account to rename or remove it.

## Install

```bash
brew install --cask amanv8060/tap/claude-switcher
```

Or download the zip from [Releases](https://github.com/amanv8060/claude-switcher/releases), unzip it
and move **Claude Switcher.app** to Applications. The app isn't notarized yet, so macOS blocks it
the first time you open it. Right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/Claude Switcher.app"
```

Then click the menu bar icon and choose **Add account** to sign in to your other accounts.

## How it works

| | What a switch changes |
| --- | --- |
| **Claude Code** | The login in the `Claude Code-credentials` keychain item, and the `oauthAccount` entry in `~/.claude.json`. MCP logins and other settings are left alone. |
| **Claude Desktop** | Claude quits, its data folder (`~/Library/Application Support/Claude`) is swapped for the other account's copy, and Claude reopens. Each account keeps its own copy. |

Usage comes from the same endpoint Claude Code's `/usage` command uses, and refreshes every five
minutes.

A few things to know:

- Claude Code sessions that are already running keep the old account until you restart them.
- Switching Claude Desktop stops any chats or Code sessions running in it. You're asked first.
- Continuing a session under a different account starts without the prompt cache, because
  caches aren't shared between accounts. The first message after the switch re-processes the
  whole conversation and uses noticeably more of the new account's limit; later messages are
  cached again. To keep that cost down, switch between tasks rather than in the middle of a long
  one, run `/compact` before moving a long session, and avoid switching back and forth.
- Add accounts with **Add account** (it runs `claude auth login`). Don't use `claude auth logout`
  to change accounts: logging out can revoke the login the switcher saved.

## Privacy

Saved logins live in your login keychain, never in plain files. The app talks only to
`api.anthropic.com` and `platform.claude.com`, and only with each account's own login. There's no
analytics or telemetry. [SECURITY.md](SECURITY.md) lists every file the app touches.

## Building from source

Requires macOS 13 or later and the Xcode command line tools. There are no dependencies.

```bash
git clone https://github.com/amanv8060/claude-switcher.git
cd claude-switcher
./build.sh --install   # builds, copies to ~/Applications, turns on launch at login
```

`./build.sh` on its own builds into `build/` without installing.

## Contributing

Issues and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers the project layout,
commit style and how releases work.

## License

[MIT](LICENSE). Not affiliated with Anthropic. Claude Switcher relies on undocumented parts of
Claude Code and Claude Desktop, so an update to either can break it.
