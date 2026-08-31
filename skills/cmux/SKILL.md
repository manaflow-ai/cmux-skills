---
name: cmux
description: "Main entry point and router for cmux. Use whenever the user invokes $cmux or asks broadly about cmux, including phrases such as '$cmux workspaces', '$cmux config', '$cmux browser', '$cmux CLI', '$cmux sidebar', or '$cmux cloud'. Explain cmux when needed, select and read the smallest relevant installed cmux subskill, and coordinate cross-cutting cmux tasks."
---

# cmux

Treat `$cmux` as the single front door to cmux. Infer the requested capability, route to the smallest relevant focused skill, read that skill completely, then do the work. The word after `$cmux` is an intent hint, not necessarily an exact skill name.

## Route

Use the available skill catalog first. If the focused cmux skills are not listed there, look for sibling `cmux-*/SKILL.md` files beside this skill or in the active agent's skill roots. Inspect only their frontmatter descriptions until a route is selected.

| User intent | Read |
|---|---|
| CLI commands, command discovery, socket API, notifications, hooks, feed, SSH, Claude teams, panes or surfaces through `cmux ...` | `cmux-cli` |
| Current/caller workspace, splits, tabs, helper panes, opening files beside the work, tagged sockets, non-disruptive layout | `cmux-workspace` |
| Browser/webview, opening a site in cmux, snapshots, DOM interaction, forms, screenshots, cookies, storage, console or downloads | `cmux-browser` |
| Settings, config, `cmux.json`, shortcuts, appearance, standard preferences, custom actions, menus, sidebar entries or workspace groups | `cmux-config` |
| Pasted `workspace:`, `pane:`, `surface:`, `window:` refs, UUIDs, or context blocks with cmux IDs | `cmux-ref` first |
| Custom left sidebar, sidebar builder, interpreted Swift view, `~/.config/cmux/sidebars/*.swift` | `cmux-sidebar-builder` |
| HTML walkthrough, demo, evidence page, verification report, durable screenshots/logs, artifact preview | `cmux-artifact` |
| Self-hosted cmux Cloud VM image, Freestyle snapshot, `FREESTYLE_SANDBOX_SNAPSHOT` | `cmux-freestyle` |

Also consider any installed, repository-local `cmux-*` skill whose description is a closer match. This lets `$cmux` route to newer or private extensions without hard-coding them here.

## Combine

Use multiple skills only when the outcome crosses boundaries. Read them in this order:

1. Targeting: `cmux-ref` when explicit IDs were supplied.
2. Context: `cmux-workspace` when acting in the caller workspace.
3. Capability: `cmux-browser`, `cmux-config`, `cmux-cli`, or another focused extension.
4. Output: `cmux-artifact` when producing durable evidence.

Common combinations:

- `$cmux browser open localhost beside me`: `cmux-workspace`, then `cmux-browser`.
- `$cmux config the plus menu`: `cmux-config`; add `cmux-cli` only if live command syntax is required.
- `$cmux click surface:7`: `cmux-ref`, then `cmux-browser` or `cmux-cli` based on the surface type.
- `$cmux make a verification page and show it`: `cmux-artifact`, then `cmux-workspace`.

Do not load every cmux skill preemptively.

## Explain cmux

For broad questions such as "what can cmux do?", comparisons, onboarding, or a route whose focused skill is unavailable, read [references/overview.md](references/overview.md). For exact current command syntax, use the installed CLI:

```bash
cmux --help
cmux <command> --help
cmux docs
```

When a selected focused skill is missing, continue with the overview, live help, and local cmux docs or source. State briefly that the focused skill was unavailable. Do not claim to have read a missing skill.

## Rules

- Preserve explicit workspace, pane, surface, window, and socket targets throughout the task.
- Default mutations to the caller workspace from `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, and `CMUX_SOCKET_PATH`, not whichever window is visually focused.
- Avoid focus changes, closing user state, or sending input outside the named target unless the user explicitly requests it.
- Discover exact CLI syntax from live help instead of relying on examples from memory.
- Route persistent preferences and customization through `cmux-config`; do not use one-off `defaults write` commands as a substitute.
- Prefer the focused skill's instructions when they conflict with this overview.
- Keep routing invisible unless naming the selected skill helps explain the action or a required skill is missing.
