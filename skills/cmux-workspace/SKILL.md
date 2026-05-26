---
name: cmux-workspace
description: "Work inside the current cmux workspace and terminal. Use for cmux workspace, current workspace, caller surface, panes, surfaces, tagged reloads, socket targeting, and non-interfering cmux automation."
---

# cmux Workspace

Use this skill when a task should be scoped to the cmux workspace that invoked the agent. A workspace is the sidebar tab-like unit in cmux. It contains split panes, and each pane contains one or more surfaces. A surface is the terminal or browser session the user interacts with.

## Default Rule

Scope actions to the current caller workspace unless the user explicitly asks for another workspace, another window, or global state.

Do not assume the visually focused cmux workspace is the right target. An agent can be running in one workspace while the user is looking at another. Prefer the caller environment first:

```bash
printf 'workspace=%s\nsurface=%s\nsocket=%s\n' \
  "${CMUX_WORKSPACE_ID:-}" \
  "${CMUX_SURFACE_ID:-}" \
  "${CMUX_SOCKET_PATH:-}"
cmux identify --json
```

Use `CMUX_WORKSPACE_ID` as the default workspace anchor and `CMUX_SURFACE_ID` as the default caller terminal/surface anchor. If those are missing, use `cmux identify --json` and be explicit that you are using the currently focused cmux context.

## Non-Disruptive Automation

The user may be visually focused on a different workspace, window, or app while an agent works in the caller workspace. Treat layout and focus as separate concerns. Never call focus-changing verbs speculatively.

Never call these without an explicit user ask:

- `select-workspace` switches the visible sidebar tab.
- `focus-pane` / `focus-panel` yanks pane or surface focus.
- `tab-action` with focus-changing actions.

These are user-affecting actions, like clicks. The rule applies even inside the caller's own workspace, since the user may be looking elsewhere.

Build layout additively, in one shot. Prefer commands that create a new pane already populated with the right surface:

```bash
# pane and content in one call, no follow-up needed
cmux new-pane --workspace "${CMUX_WORKSPACE_ID}" --type browser --direction right --url "http://127.0.0.1:8765"
cmux new-pane --workspace "${CMUX_WORKSPACE_ID}" --type terminal --direction down
```

Avoid create-then-move-then-focus chains. If a layout command rejects a valid `surface:` or `pane:` ref, do not work around it by focusing. Report the bug to the user and stop.

Pass `--focus false` whenever the verb supports it. `move-surface --focus false` preserves the user's current attention. Other commands may grow the same flag over time (https://github.com/manaflow-ai/cmux/issues/1418, https://github.com/manaflow-ai/cmux/issues/2820).

## Right-Side Helper Pane

When opening auxiliary output for the current task (preview apps, TUIs, logs, one-off shells, browser checks), keep the workspace organized by reusing a helper pane to the right of the caller terminal.

First inspect the caller context and panes:

```bash
cmux identify --json
cmux list-panes --workspace "${CMUX_WORKSPACE_ID:-}" --json
cmux list-pane-surfaces --workspace "${CMUX_WORKSPACE_ID:-}" --json
```

Use this policy:

- If the caller workspace already has a non-caller helper pane, add a new surface to that pane instead of creating another pane:
  ```bash
  cmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" --pane pane:<helper> --type terminal --focus false
  ```
- If there is no helper pane, create exactly one right-side pane:
  ```bash
  cmux new-pane --workspace "${CMUX_WORKSPACE_ID:-}" --type terminal --direction right --focus false
  ```
- If there are multiple obvious stale helper panes from this same automation and the user asked to tidy or reuse, keep one right helper pane and clean up the duplicates. Do not close panes you cannot confidently identify as stale helper output.
- Send commands to the new or reused helper surface by explicit surface ref. Do not focus it unless the user asks.

This means repeated "open it" requests should normally create tabs inside the existing right helper pane, not more splits.

After creating a helper terminal, verify that it is usable before claiming work is visible there:

```bash
cmux surface-health --workspace "${CMUX_WORKSPACE_ID:-}"
cmux read-screen --workspace "${CMUX_WORKSPACE_ID:-}" --surface surface:<helper> --lines 20
cmux top --workspace "${CMUX_WORKSPACE_ID:-}" --processes --format tsv
```

If `read-screen` reports `Terminal surface not found`, or `surface-health` shows the helper terminal is not attached and `top` shows no process for it, treat that as a cmux CLI/runtime bug. Do not claim the command is running in the workspace. Clean up any empty helper surfaces you created, then report the bug or use an already-materialized cmux terminal surface. Do not use hidden `tmux`, `nohup`, or detached background fallbacks for visible dogfood handoff unless the user explicitly asks for that workaround.

## Artifact Previews

When a task produces videos, images, checked frames, screenshots, PDFs, or other user-facing artifacts, open the final artifacts in cmux before handoff. Put them in the caller workspace's right-side helper pane as file preview tabs, and use `--no-focus` so the user's current terminal stays selected.

Final user-facing artifacts should persist under `/cmux-assets/<branch>/...`. If `/cmux-assets` cannot be created because the root volume is read-only, use `cmux-assets/<branch>/...` under the current repo checkout and state that fallback. Use `/tmp` only for scratch, then copy accepted artifacts into the durable tree before opening or reporting them.

Use absolute durable paths or paths relative to the current repo checkout. If the artifact lives in a worktree, copy it into the durable branch-scoped asset tree before final handoff; do not report paths that only work from inside the worktree.

Resolve the workspace and pane in this order:

1. Prefer `CMUX_WORKSPACE_ID` and `CMUX_SURFACE_ID`.
2. If those are missing or rejected by `cmux`, inspect `cmux identify --json` and state that you are falling back to the current focused cmux context.
3. Reuse an existing non-caller helper pane when obvious.
4. If no helper pane exists, create one on the right with `--focus false`, then re-list panes to get the pane ref.

Template:

```bash
ARTIFACTS=(
  "/cmux-assets/<branch>/demos/demo.mov"
  "/cmux-assets/<branch>/demos/frame-tail.png"
)

WORKSPACE="${CMUX_WORKSPACE_ID:-}"
SURFACE="${CMUX_SURFACE_ID:-}"

cmux identify --json
cmux list-panes --workspace "$WORKSPACE" --json
cmux list-pane-surfaces --workspace "$WORKSPACE" --json

# Pick an existing non-caller helper pane from the pane list. If none exists:
cmux new-pane --workspace "$WORKSPACE" --type terminal --direction right --focus false
cmux list-panes --workspace "$WORKSPACE" --json

cmux open "${ARTIFACTS[@]}" \
  --workspace "$WORKSPACE" \
  --pane pane:<right-helper> \
  --no-focus
cmux list-pane-surfaces --workspace "$WORKSPACE" --json
```

If `cmux open` fails because the caller env points at a stale workspace, retry once with the refs from `cmux identify --json`. Do not keep guessing across other workspaces. If opening still fails, report the failure and include the exact artifact paths.

## Hierarchy

- Window: a macOS cmux window.
- Workspace: a sidebar entry. The UI may call it a tab, but CLI/socket APIs call it a workspace.
- Pane: a split region inside a workspace.
- Surface: a tab inside a pane. Surfaces can be terminals or browser panels.
- Panel: internal content type inside a surface. Prefer CLI surface commands instead of panel internals.

## Inspect Current Context

```bash
cmux identify --json
cmux current-workspace --json
cmux list-workspaces --json
cmux list-panes --workspace "${CMUX_WORKSPACE_ID:-}" --json
cmux list-pane-surfaces --workspace "${CMUX_WORKSPACE_ID:-}" --json
cmux list-panels --workspace "${CMUX_WORKSPACE_ID:-}" --json
```

Use `--id-format both` when logs or handoffs need stable UUIDs plus human refs:

```bash
cmux --json --id-format both identify
```

## Workspace-Scoped Actions

Prefer explicit workspace flags even when env vars are set. It makes automation auditable and avoids affecting a focused workspace in another window.

```bash
# create a new workspace when the user asks for a new task area
cmux new-workspace --name "debug auth" --cwd "$PWD"

# rename / close (only when explicitly requested)
cmux rename-workspace --workspace "${CMUX_WORKSPACE_ID:-}" -- "build fix"
cmux close-workspace --workspace workspace:4
cmux close-surface --workspace "${CMUX_WORKSPACE_ID:-}" --surface surface:3

# additive layout (safe, no focus side effects beyond the command's own defaults)
cmux new-pane --workspace "${CMUX_WORKSPACE_ID:-}" --type terminal --direction right
cmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" --type terminal

# focus-changing (USER-AFFECTING, only on explicit ask, see Non-Disruptive Automation above)
cmux select-workspace --workspace workspace:2
cmux focus-pane --workspace "${CMUX_WORKSPACE_ID:-}" --pane pane:2
cmux focus-panel --workspace "${CMUX_WORKSPACE_ID:-}" --panel surface:3
```

## Caller Terminal

The current terminal is the surface that invoked the agent. Treat it as the safest anchor for relative operations.

```bash
# send to the focused terminal in the caller workspace
cmux send "npm test\n"

# send to the exact caller surface
cmux send --surface "${CMUX_SURFACE_ID:-}" "git status\n"
cmux send-key --surface "${CMUX_SURFACE_ID:-}" enter
```

Do not send keystrokes, close surfaces, or change focus in other workspaces unless the user asked for that target.

## Moving Surfaces

Reorder a surface within its pane:

```bash
cmux move-surface --surface "${CMUX_SURFACE_ID}" --before surface:3
cmux move-surface --surface "${CMUX_SURFACE_ID}" --after surface:3
cmux move-surface --surface "${CMUX_SURFACE_ID}" --index 0
```

Move a surface to another existing pane. Pass `--focus false` to keep the user's current attention put:

```bash
cmux move-surface --surface surface:240 --pane pane:172 --focus false
```

Split a surface off into a new pane:

```bash
cmux drag-surface-to-split --surface surface:240 down
```

Known papercut: `drag-surface-to-split` currently routes through V1 and resolves the workspace via UI focus, so it can fail with `ERROR: Surface not found` when the caller's workspace is not the visually focused one. Tracked at https://github.com/manaflow-ai/cmux/issues/1901, related to https://github.com/manaflow-ai/cmux/issues/3189. Until that lands, prefer building the layout additively (see Non-Disruptive Automation above) over create-then-split.

Do not call `focus-pane` or `focus-panel` to recover from a failed move. Report the failure and stop.

## Sidebar State

Status, progress, and logs should usually be attached to the current workspace so the sidebar reflects this task.

```bash
cmux set-status build "running" --workspace "${CMUX_WORKSPACE_ID:-}" --color "#ff9500"
cmux set-progress 0.4 --label "Building" --workspace "${CMUX_WORKSPACE_ID:-}"
cmux log --workspace "${CMUX_WORKSPACE_ID:-}" --level info -- "Started build"
cmux sidebar-state --workspace "${CMUX_WORKSPACE_ID:-}" --json
cmux clear-status build --workspace "${CMUX_WORKSPACE_ID:-}"
cmux clear-progress --workspace "${CMUX_WORKSPACE_ID:-}"
```

## Rebuild and Reload

For cmux app/runtime changes, use tagged reloads from the active worktree. A tagged reload creates an isolated app name, bundle ID, debug socket, and DerivedData path.

```bash
./scripts/reload.sh --tag <short-tag>
```

If reload output includes `Dev web origin`, start the matching dev server from the same worktree before handoff and prove it responds:

```bash
cd web
CMUX_PORT=<printed-port> CMUX_PORT_RANGE=<range> CMUX_PORT_END=<end> bun dev
curl -fsS "http://127.0.0.1:<printed-port>"
```

Run that server in the right-side helper terminal and verify the terminal exists with `read-screen` or `top`. If the helper terminal cannot be instantiated, report the cmux CLI/runtime bug instead of using a hidden background fallback.

Never build or launch untagged `cmux DEV`. If tests or tools need a socket, use the tag-specific socket:

```bash
CMUX_SOCKET_PATH=/tmp/cmux-debug-<short-tag>.sock cmux identify --json
```

When a task touches shared iOS/runtime code, also run the iOS reload flow from the worktree:

```bash
ios/scripts/reload.sh --tag <ios-tag>
```

## Socket and Access

Use the socket path provided by cmux before falling back to defaults:

```bash
SOCK="${CMUX_SOCKET_PATH:-/tmp/cmux.sock}"
```

Socket access can be off, restricted to cmux-spawned processes, or allow all local processes. If a command cannot connect, inspect capabilities before changing settings:

```bash
cmux capabilities --json
cmux ping
```

## References

- [references/commands.md](references/commands.md) enumerates workspace, pane, surface, notification, and utility commands.
- [../cmux-browser/SKILL.md](../cmux-browser/SKILL.md) covers browser surfaces with the same current-workspace rule.

## Rules

- Work in the current caller workspace by default.
- Use `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, and `CMUX_SOCKET_PATH` before focused-window fallbacks.
- Prefer explicit `--workspace` and `--surface` flags for mutating actions.
- Never call `focus-pane`, `focus-panel`, `select-workspace`, or focus-changing `tab-action` verbs unless the user explicitly asked. The user may be visually on a different workspace, window, or app.
- Pass `--focus false` on `move-surface` and any creation verb that supports it.
- For auxiliary output, reuse the right-side helper pane; create one only if it does not exist.
- Persist final videos, images, checked frames, and other user-facing artifacts under `/cmux-assets/<branch>/...` or the explicit fallback `cmux-assets/<branch>/...`, then open them in the right-side helper pane with `cmux open ... --no-focus` before handoff.
- Build layout additively with `new-pane --type ... --url ...` rather than create-then-move-then-focus chains.
- If a CLI command rejects a valid surface or pane ref, report it to the user. Do not work around by focusing.
- Do not close, focus, move, or send input to another workspace unless the user names that target.
- Use short refs for chat and command examples. Use UUIDs only for logs, persistence, or debugging.
- For app/runtime changes, always reload with `./scripts/reload.sh --tag <tag>` from the worktree before dogfood handoff.
- If a tagged reload prints `Dev web origin`, the handoff is incomplete until the same-worktree dev server is running and `curl -fsS <Dev web origin>` passes.
