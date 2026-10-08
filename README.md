# cc-switcher

A macOS menu bar app for switching between multiple Claude accounts and seeing each one's usage limits.

## Features

- **One click switches everywhere.** Each account is listed once. Clicking it switches the
  Claude Code CLI and then the Claude Desktop app, including its Code tab, which uses the
  Desktop app's login. Desktop logins are matched to CLI logins automatically by account ID.

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

The first time you switch to an account that has never signed in to Claude Desktop, the app
offers to set that up: Claude reopens signed out, you sign in, and the login is linked to that
account from then on. Switching Desktop accounts restarts Claude, which stops chats and Code
sessions running in it. You're asked first unless you turn that off under **Manage**.
**Manage → Add Claude Desktop login…** adds a Desktop-only account.

## Notes

- Claude Code rotates refresh tokens. The switcher re-saves the active login before every switch
  and whenever the menu opens. When it refreshes an expired token to read usage, it writes the
  new token back everywhere that token is stored.
- `~/.claude.json` is backed up to `~/.claude.json.switcher-backup` before each switch.
- Self-test (read-only unless the token has expired): `"build/Claude Switcher.app/Contents/MacOS/ClaudeSwitcher" --selftest --usage`
- This isn't an official Anthropic tool. It relies on undocumented internals that may change.
