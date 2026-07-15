# cmux overview

Read this reference for broad explanations, onboarding, comparisons, or when a focused cmux skill is unavailable. Use focused skills and live `cmux --help` for procedures and exact syntax.

## Product model

cmux is a native macOS terminal built on libghostty for people running several coding agents and development tasks at once. It keeps terminal workflows open-ended while adding visible organization, notifications, an in-app browser, and a programmable CLI.

The UI hierarchy is:

```text
app
└── window
    └── workspace        sidebar item / task container
        └── pane         one region in a split layout
            └── surface  tab inside a pane, such as a terminal or browser
```

A window contains workspaces. A workspace contains split panes. Each pane contains one or more tab-like surfaces. CLI refs such as `workspace:2`, `pane:3`, and `surface:7` identify these objects for automation.

## Main capabilities

| Area | What cmux provides | Focused skill |
|---|---|---|
| Terminals | GPU-accelerated Ghostty terminals, Ghostty themes/fonts/config compatibility, tabs and horizontal or vertical splits | `cmux-workspace`, `cmux-cli` |
| Workspaces | Vertical task tabs with cwd, Git branch, linked PR, listening ports, status, progress, and recent notification context | `cmux-workspace` |
| Notifications | Attention rings, unread state, notification panel, OSC notification support, and `cmux notify` for agent hooks | `cmux-cli` |
| Browser | WKWebView surfaces beside terminals, authenticated browser import, accessibility snapshots, DOM actions, JavaScript, screenshots, downloads, storage, and diagnostics | `cmux-browser` |
| Automation | Unix-socket CLI for creating and inspecting workspaces, panes, and surfaces; sending input; opening content; and publishing sidebar state | `cmux-cli` |
| Configuration | `~/.config/cmux/cmux.json` settings plus project-local `.cmux/cmux.json` customization, commands, menus, actions, shortcuts, and groups | `cmux-config` |
| Custom sidebars | Left-sidebar views authored with cmux's runtime SwiftUI-style interpreter | `cmux-sidebar-builder` |
| Remote work | `cmux ssh` workspaces whose browser traffic follows the remote network, so remote localhost URLs work in browser panes | `cmux-cli`, `cmux-workspace` |
| Agent teams | Native panes and sidebar metadata for agent sessions, including Claude Code teammate workflows | `cmux-cli`, `cmux-workspace` |
| Evidence | Durable HTML walkthroughs, logs, screenshots, videos, and verification pages opened beside the task | `cmux-artifact` |
| Cloud VMs | cmux Cloud workflows and an optional self-hosted Freestyle VM snapshot path | `cmux-freestyle` |

## Configuration boundaries

- Ghostty appearance and terminal behavior belong in `~/.config/ghostty/config` when Ghostty already provides the option.
- cmux preferences and user-level customization belong in `~/.config/cmux/cmux.json`.
- Project-specific cmux commands and actions can live in `.cmux/cmux.json`.
- Custom interpreted left sidebars live under `~/.config/cmux/sidebars/*.swift`.
- Session layout is app-managed state. Use cmux CLI commands rather than editing session files directly.

## Automation context

A process launched inside cmux may receive:

```text
CMUX_WORKSPACE_ID
CMUX_SURFACE_ID
CMUX_SOCKET_PATH
```

These describe the caller, which can differ from the workspace or app currently visible to the user. Safe automation keeps that context explicit, creates helper panes without stealing focus, and reuses returned refs for later actions.

The installed CLI and bundled docs are the source of truth for a user's version:

```bash
cmux version
cmux capabilities --json
cmux --help
cmux docs
cmux docs settings
cmux docs shortcuts
cmux docs browser
cmux docs agents
```

## Product principle

cmux exposes composable primitives: terminals, browsers, notifications, workspaces, splits, surfaces, configuration, and a CLI. It does not require a particular coding-agent workflow. Prefer composing those primitives around the user's existing workflow.
