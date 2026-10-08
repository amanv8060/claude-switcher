# Security

Claude Switcher handles login tokens for your Claude accounts, so security reports are very welcome.

## Reporting

Please **don't open a public issue**. Use [GitHub's private vulnerability reporting](https://github.com/amanv8060/claude-switcher/security/advisories/new) instead. You'll get a reply within a few days.

## What the app does with your data

- **Saved logins** are stored in your login keychain under the service `ClaudeSwitcher`. Nothing secret is written to plain files.
- **The account list** (`~/Library/Application Support/ClaudeSwitcher/state.json`) contains names, emails and account IDs, but no tokens.
- **Network:** the app only talks to `api.anthropic.com` (usage) and `platform.claude.com` (token refresh), and only with the token for the account being asked about. There's no analytics or telemetry, and it doesn't contact any other server.
- **Files it changes:** the `Claude Code-credentials` keychain item (only the `claudeAiOauth` key), `~/.claude.json` (only `oauthAccount`, with a backup in `~/.claude.json.switcher-backup`), and Claude Desktop's data folder (renamed, never deleted, except when you remove a profile, which moves it to the Trash).
