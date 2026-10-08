# cc-switcher

A macOS menu bar app for switching between multiple Claude accounts and seeing each one's usage limits.

## Features

- **Claude Code (CLI) accounts.** Switch with one click. Only the Claude login is swapped: the
  `claudeAiOauth` token in the `Claude Code-credentials` keychain item and `oauthAccount` in
  `~/.claude.json`. MCP tokens and every other setting stay as they are.
- **Usage limits for every account.** Shows session (5-hour) and weekly utilization, plus
  Opus/Sonnet weekly limits when your plan has them, with reset times. The data comes from the
  same endpoint as Claude Code's `/usage` and refreshes every 5 minutes. The active account's
  session % is shown in the menu bar.
- **Claude Desktop accounts.** Each account keeps its own copy of
  `~/Library/Application Support/Claude`. A switch quits Claude, swaps the folder (a rename) and
  relaunches it.
- Saved logins live in your login keychain (service `ClaudeSwitcher`), never in plain files.

## Install

Requires macOS 13+ and Xcode command line tools.

```bash
./build.sh
cp -R "build/Claude Switcher.app" ~/Applications/
open ~/Applications/"Claude Switcher.app"
```

Turn on **Manage → Launch at login** if you want it to start automatically.

## Usage

**Add a Claude Code account:** choose **Add account…**. Your current login is saved, then
Terminal runs `claude auth login`. Sign in with the other account and it shows up in the menu.
Click an account to switch. Restart any `claude` sessions that were already running.

> Don't use `claude auth logout` to change accounts. It can revoke the saved login.

**Add a Claude Desktop account:** choose **Save current login as profile…** once, then
**Add account…**. Claude reopens signed out so you can log in.

## Notes

- Claude Code rotates refresh tokens. The switcher re-saves the active login before every switch
  and whenever the menu opens. When it refreshes an expired token to read usage, it writes the
  new token back everywhere that token is stored.
- `~/.claude.json` is backed up to `~/.claude.json.switcher-backup` before each switch.
- Self-test (read-only unless the token has expired): `"build/Claude Switcher.app/Contents/MacOS/ClaudeSwitcher" --selftest --usage`
- This isn't an official Anthropic tool. It relies on undocumented internals that may change.
