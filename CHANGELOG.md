# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-10-09

### Added

- Update checks. Once a day (or from settings) the app looks for a newer release. When one is
  available, **Update** upgrades it through Homebrew, or opens the release page for other installs.
  Turn it off with **Check for updates automatically**.

### Changed

- When Claude Code and Claude Desktop are on different accounts, the current account shows where
  each one is, with a single button that says what it will do. The account Desktop is on is
  tagged **In Desktop**.

## [1.2.1] - 2026-10-09

### Fixed

- Sessions started in a scratch workspace reported that their working folder no longer existed
  after a Claude Desktop switch. Working folders now move along with every switch.
- **Add account** opened Terminal into "command not found" when Claude Code wasn't installed. It
  now explains how to install it, and finds the `claude` command even when it isn't on your PATH.

## [1.2.0] - 2026-10-09

### Added

- An opt-in setting, **Share Code sessions across accounts**, that shows the same Claude Desktop
  Code sessions under every account. The newest copy of a session wins, and deleting a session
  under one account deletes it everywhere.

### Fixed

- Sessions deleted in Claude Desktop could be copied back from another profile on the next switch.

## [1.1.0] - 2026-10-09

### Added

- Claude Desktop Code and agent sessions are kept in sync across Desktop profiles, so switching
  accounts no longer hides history that was saved in another profile.
- A warning when a Desktop profile gets signed in to a different account than the one it was set
  up for, with options to keep the new account or rename the profile.

### Fixed

- Only the Desktop profile that's actually in use shows as active. Previously, two profiles signed
  in to the same account could both look current, hiding the one that held your sessions.

## [1.0.1] - 2026-10-09

### Added

- The settings menu shows the installed version and links to the releases page.

## [1.0.0] - 2026-10-08

First release.

### Added

- Menu bar popover listing your Claude accounts, with the current one at the top.
- One-click switching for the Claude Code CLI and Claude Desktop, including its Code tab.
  Desktop logins are paired with CLI logins automatically.
- Session and weekly usage limits for every account (plus Opus and Sonnet limits where the plan
  has them), with reset times and pace in tooltips.
- A suggestion to switch to the account with the most room left.
- Plan names, ⌘1–⌘9 shortcuts, launch at login, and a menu bar label showing the current account
  and its session usage.

[1.3.0]: https://github.com/amanv8060/claude-switcher/releases/tag/v1.3.0
[1.2.1]: https://github.com/amanv8060/claude-switcher/releases/tag/v1.2.1
[1.2.0]: https://github.com/amanv8060/claude-switcher/releases/tag/v1.2.0
[1.1.0]: https://github.com/amanv8060/claude-switcher/releases/tag/v1.1.0
[1.0.1]: https://github.com/amanv8060/claude-switcher/releases/tag/v1.0.1
[1.0.0]: https://github.com/amanv8060/claude-switcher/releases/tag/v1.0.0
