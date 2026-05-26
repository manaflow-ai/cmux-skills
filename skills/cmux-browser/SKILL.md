---
name: cmux-browser
description: "Automate the browser inside cmux. Use for cmux browser, browser surface, webview, current workspace browser, snapshot refs, DOM actions, waits, screenshots, cookies, storage, tabs, downloads, console, errors, and browser session state."
---

# cmux Browser

Use this skill for browser automation inside cmux webview surfaces. It is different from a standalone browser automation tool because every browser surface lives inside a cmux workspace, pane, and surface topology.

## Default Rule

Open and control browser surfaces in the current caller workspace unless the user explicitly names another workspace or window.

Before mutating browser state, identify the caller:

```bash
printf 'workspace=%s\nsurface=%s\nsocket=%s\n' \
  "${CMUX_WORKSPACE_ID:-}" \
  "${CMUX_SURFACE_ID:-}" \
  "${CMUX_SOCKET_PATH:-}"
cmux identify --json
```

Use `CMUX_WORKSPACE_ID` for new browser splits and `CMUX_SURFACE_ID` to understand the terminal that invoked the automation. Do not open a browser in the visually focused workspace if it differs from the caller workspace.

## Core Workflow

```bash
# Open in the caller workspace and capture the returned surface ref.
cmux --json browser open https://example.com --workspace "${CMUX_WORKSPACE_ID:-}"

# Use the returned surface, for example surface:7.
cmux browser surface:7 get url
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 snapshot --interactive --compact
cmux browser surface:7 click e2 --snapshot-after
cmux browser surface:7 snapshot --interactive --compact
```

Loop: navigate, verify URL, wait, snapshot, act, then re-snapshot. Snapshot refs are temporary. Re-snapshot after navigation, modal changes, tab changes, or DOM updates.

## Targeting

Most subcommands require a browser surface:

```bash
cmux browser identify
cmux browser identify --surface surface:2
cmux browser surface:2 get url
cmux browser --surface surface:2 get title
```

Open commands can create or reuse a browser split:

```bash
cmux browser open http://localhost:3000 --workspace "${CMUX_WORKSPACE_ID:-}" --json
cmux browser open-split https://example.com --workspace workspace:2 --json
cmux browser new https://example.com --window window:1 --json
```

Keep one browser surface per task unless the user asks for multiple tabs or pages.

## Command Groups

See [references/commands.md](references/commands.md) for the full command list. Main groups:

- Navigation and targeting: `identify`, `open`, `open-split`, `new`, `navigate`, `goto`, `back`, `forward`, `reload`, `url`, `focus-webview`, `is-webview-focused`.
- Waiting: `wait --selector`, `--text`, `--url-contains`, `--load-state`, `--function`.
- DOM interaction: `click`, `dblclick`, `hover`, `focus`, `check`, `uncheck`, `scroll-into-view`, `type`, `fill`, `press`, `keydown`, `keyup`, `select`, `scroll`.
- Inspection: `snapshot`, `screenshot`, `get`, `is`, `find`, `highlight`.
- JavaScript and injection: `eval`, `addinitscript`, `addscript`, `addstyle`.
- Frames, dialogs, downloads: `frame`, `dialog`, `download`.
- State and session: `cookies`, `storage`, `state`.
- Tabs and diagnostics: `tab`, `console`, `errors`.
- Environment and lower-level APIs: `viewport`, `geolocation`, `offline`, `trace`, `network`, `screencast`, `input`.

## Common Patterns

### Durable Captures

Save browser screenshots, traces, downloaded diagnostics, and reusable session state under `/cmux-assets/<branch>/browser/...`, not `/tmp`, before reporting them to the user.

```bash
BRANCH="$(git branch --show-current 2>/dev/null || true)"
BRANCH="${BRANCH:-$(basename "$PWD")}"
BRANCH="$(printf '%s' "$BRANCH" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//;s/-$//')"
ASSET_BASE="/cmux-assets"
if ! mkdir -p "$ASSET_BASE/$BRANCH" 2>/dev/null; then
  ASSET_BASE="$(pwd)/cmux-assets"
  mkdir -p "$ASSET_BASE/$BRANCH"
fi
BROWSER_ASSET_ROOT="$ASSET_BASE/$BRANCH/browser/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BROWSER_ASSET_ROOT"
```

If `/cmux-assets` is unavailable because the root volume is read-only, use the fallback path and state it. Do not leave final screenshots or session files only in `/tmp`.

### Navigate, Wait, Inspect

```bash
cmux --json browser open http://localhost:3000 --workspace "${CMUX_WORKSPACE_ID:-}"
cmux browser surface:7 get url
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 snapshot --interactive --compact
cmux browser surface:7 get title
```

### Form Fill

```bash
cmux browser surface:7 fill "#email" --text "ops@example.com"
cmux browser surface:7 fill "#password" --text "$PASSWORD"
cmux browser surface:7 click "button[type='submit']" --snapshot-after
cmux browser surface:7 wait --text "Welcome" --timeout-ms 15000
cmux browser surface:7 is visible "#dashboard"
```

### Debug Capture

```bash
cmux browser surface:7 console list
cmux browser surface:7 errors list
cmux browser surface:7 screenshot --out "$BROWSER_ASSET_ROOT/cmux-failure.png"
cmux browser surface:7 snapshot --interactive --compact
```

### Session Save and Restore

```bash
cmux browser surface:7 state save "$BROWSER_ASSET_ROOT/cmux-browser-session.json"
cmux browser surface:7 state load "$BROWSER_ASSET_ROOT/cmux-browser-session.json"
cmux browser surface:7 reload --snapshot-after
```

## Remote Workspaces

In remote SSH workspaces, browser panes route HTTP and WebSocket traffic through the remote machine. `localhost:3000` means the remote host's localhost, and browser storage is isolated per remote workspace context.

## Rebuild and Reload

If browser automation is validating a cmux app/runtime change, first build a tagged app from the active worktree:

```bash
./scripts/reload.sh --tag <short-tag>
CMUX_SOCKET_PATH=/tmp/cmux-debug-<short-tag>.sock cmux browser open http://localhost:3000 --workspace "${CMUX_WORKSPACE_ID:-}"
```

Never automate against an untagged debug socket for tests or dogfood builds.

## Rules

- Scope browser opens and actions to the current caller workspace by default.
- Pass `--workspace "${CMUX_WORKSPACE_ID:-}"` when creating a browser surface from a cmux terminal.
- Use returned `surface:N` refs, and re-snapshot after any state-changing action.
- Verify `get url` before waiting or diagnosing page state.
- Use `--snapshot-after` on mutating actions when you need immediate verification.
- Prefer `get`, `is`, and `find` for scripts. Use screenshots and snapshots for human review.
- Do not close, move, or focus browser surfaces outside the caller workspace unless the user names that target.
- Do not use unsupported standalone-browser assumptions. cmux uses WKWebView-backed browser surfaces.
