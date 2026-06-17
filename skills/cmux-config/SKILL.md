---
name: cmux-config
description: "Configure cmux through ~/.config/cmux/cmux.json: settings (appearance, sidebar, notifications, automation, browser, shortcuts, set/get/validate by JSON path), customization (tab bar buttons, plus-button click and right-click menus, custom actions/commands/menus, right sidebar), and sidebar workspace groups (anchor workspaces, group CLI/socket ops, per-cwd group config). Triggers: 'cmux config', 'cmux.json', 'change cmux setting', 'set <x> in cmux', 'rebind a cmux shortcut', 'cmux-customize', 'customize cmux', 'tab bar button', 'add cmux action', 'workspace group', 'group sidebar', 'anchor workspace', 'workspaceGroups'."
---

# cmux-config

Single entry point for editing a user's cmux configuration in
`~/.config/cmux/cmux.json` (JSONC). The app watches the file; saving applies
changes immediately, no restart. Legacy `~/.config/cmux/settings.json` is read
only as a fallback for keys absent from `cmux.json`.

Three areas, each with a reference:

- **Settings** — typed preferences under `app`, `terminal`, `notifications`,
  `sidebar`, `sidebarAppearance`, `workspaceColors`, `automation`, `browser`,
  `shortcuts`. See the helper below and [references/all-keys.md](references/all-keys.md) /
  [references/shortcut-actions.md](references/shortcut-actions.md).
- **Customization** — structural config: `actions`, `ui.surfaceTabBar.buttons`,
  `ui.newWorkspace` (plus-button click + context menu), `commands`, `rightSidebar`,
  `vault`. See [references/customize.md](references/customize.md).
- **Workspace groups** — collapsible anchor-owned sidebar sections via the `cmux
  workspace group` CLI / socket API and `workspaceGroups` config. See
  [references/groups.md](references/groups.md).

## Helper script

Use the bundled helper for every settings/customize read and write. It strips
JSONC comments, writes atomically, and validates keys against the schema. From the
installed skill directory:

```bash
./scripts/cmux-settings <subcommand>
```

For brevity below, assume it is on `$PATH` as `cmux-settings` (e.g.
`export PATH="$HOME/.claude/skills/cmux-config/scripts:$PATH"`).

| Command | What it does |
|---|---|
| `cmux-settings path` | Print the config path. |
| `cmux-settings dump [--no-comments]` | Print the raw file (or parsed JSON). |
| `cmux-settings get <a.b.c>` | Print value at dotted JSON path. |
| `cmux-settings set <a.b.c> <value>` | Set value (`<value>` parsed as JSON; bare words stored as strings). |
| `cmux-settings unset <a.b.c>` | Delete key, reverting to the in-app default. |
| `cmux-settings list-supported` | List every settings JSON path the app recognizes. |
| `cmux-settings validate` | Parse the file and flag unknown settings keys. |
| `cmux-settings open` | Open `cmux.json` in `$EDITOR` / VS Code / Cursor / TextEdit. |

`--file <path>` overrides the target file (use for the legacy `settings.json`).

Schema: `https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json`.

## Workflow

1. If the user named a setting in plain English, look it up first:
   `cmux-settings list-supported | rg -i '<keywords>'`.
2. Make the smallest edit (settings/customize via the helper; groups via the
   `cmux workspace group` CLI in [references/groups.md](references/groups.md)).
3. Verify by surface:
   - **Typed settings:** read back (`cmux-settings get <path>`) and `cmux-settings validate`.
   - **Customization** (`actions`, `ui.*`, `commands`, `vault`, `rightSidebar`): read back the
     exact key (`cmux-settings get <path>`) and confirm the file still parses
     (`cmux-settings dump --no-comments`). Do NOT rely on `validate` here: it skips structural
     sections, so a typo like `ui.surfaceTabbar.buttons` passes validation yet cmux ignores it.
     Check the key against [references/customize.md](references/customize.md).
   - **Groups:** `cmux workspace group list` (the settings validator does not recognize
     `workspaceGroups`).
4. Tell the user it auto-reloaded on save. No app restart. Revert with
   `cmux-settings unset <key>`.

## Rules

- Only edit `cmux.json`. Never edit `settings.json` unless asked; it is legacy.
- Never tell the user to restart cmux to apply a change; the watcher reloads on save.
- Do not blindly overwrite top-level structural sections (`actions`, `ui`,
  `commands`, `vault`, `rightSidebar`); they hold hand-tuned non-settings config.
- Color values are `#RRGGBB`; opacities are `0..1`.
- Shortcut action ids must match the schema enum; look them up in
  [references/shortcut-actions.md](references/shortcut-actions.md) before binding.
- Do not run a tagged app reload for config-only or skill-only changes.
- For workspace groups prefer CLI/socket operations over editing session JSON, and
  preserve anchor semantics (see [references/groups.md](references/groups.md)).
