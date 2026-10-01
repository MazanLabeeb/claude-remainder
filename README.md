# Claude Remainder

See what remains.

Claude Remainder is a minimal native macOS menu-bar app for checking remaining Claude Pro/Max quota across any number of Claude Code accounts.

## Why this exists

Switching between multiple Claude accounts to check session + weekly usage is slow. Claude Remainder keeps all configured accounts in one status menu with:

- Session and weekly remaining percentages
- Reset times
- Manual refresh (default)
- Optional conservative auto-refresh (15/30/60 min)
- Per-account login and profile management
- On-demand CPU/memory diagnostics

## Important caveats

- This project is unofficial and not affiliated with Anthropic.
- It reads the same undocumented OAuth usage endpoint that Claude Code uses internally (`/api/oauth/usage`).
- Anthropic may change or remove this endpoint at any time.
- Credentials are read-only; the app never writes or refreshes tokens.

## Requirements

- macOS 13+
- Swift 5.10+
- Claude Code CLI installed and usable from your shell (`claude` command)

## Quick start

```bash
git clone https://github.com/claude-remainder/claude-remainder.git
cd claude-remainder
swift build
./scripts/build-app.sh release
open "dist/Claude Remainder.app"
```

## Using multiple accounts

1. Open Claude Remainder from the menu bar.
2. Click `Add Account…`.
3. Set a name and config directory (for example `~/.claude-work`).
4. The app launches `claude auth login` in Terminal with the account's `CLAUDE_CONFIG_DIR`.
5. Repeat for as many accounts as you want.

Accounts can be edited, moved, enabled/disabled, refreshed individually, or removed without deleting keychain credentials.

## Refresh behavior

- Default mode: **manual refresh only**.
- Optional auto-refresh mode: every 15, 30, or 60 minutes.
- Backoff is applied after failures/rate limits.
- Cached snapshots remain visible if refresh fails.

## Resource usage

Use `Resource Usage…` in the menu to inspect:

- App CPU usage
- Resident memory
- Uptime
- Snapshot cache size
- Total refresh request count

Sampling runs only while the resource window is open.

## Development

```bash
swift test
swift build
```

### Packaging a `.app`

```bash
./scripts/build-app.sh release
```

## Security model

- Reads OAuth token material from:
  - Claude Code keychain entry (`Claude Code-credentials` or namespaced suffix)
  - `.credentials.json` fallback in each profile config directory
- Never stores tokens in app files
- App data in `~/Library/Application Support/ClaudeRemainder/` contains only:
  - profile settings (names/paths)
  - non-secret usage snapshots

## Project status

Early open-source release. Contributions and issue reports are welcome.
