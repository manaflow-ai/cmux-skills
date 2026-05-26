---
name: cmux-customize
description: "Customize a user's cmux configuration, including tab bar buttons, plus-button click and right-click context menu behavior, custom actions, commands, menus, right sidebar entries, and trigger phrases like cmux-customize, customize cmux, remove tab bar button, or add cmux action."
---

# cmux-customize

Use this skill for personal cmux configuration changes stored outside the app source tree, especially `~/.config/cmux/cmux.json` and project-local `.cmux/cmux.json` files. It covers action registry entries, surface tab bar buttons, plus-button click and right-click menu behavior, custom workspace commands, right sidebar wiring, and related config cleanup.

## Prerequisites

- Use the `cmux-settings` skill's `cmux-settings` helper script for global `~/.config/cmux/cmux.json` reads and writes.
- Read the `cmux-settings` skill first when the task touches standard settings under `app`, `terminal`, `notifications`, `sidebar`, `sidebarAppearance`, `workspaceColors`, `automation`, `browser`, or `shortcuts`.

## Reference

Global config:

```bash
cmux-settings path
cmux-settings dump --no-comments
```

Common structural sections in `cmux.json`:

- `actions`: action registry used by custom UI and commands.
- `ui.surfaceTabBar.buttons`: buttons shown in the surface tab bar.
- `ui.newWorkspace.action`: action triggered by a normal click on the plus button.
- `ui.newWorkspace.contextMenu`: menu items shown when right-clicking the plus button.
- `commands`: named workspace commands and layouts.
- `rightSidebar`: custom right sidebar wiring.
- `vault`: custom Vault agent registrations.

`ui.surfaceTabBar.buttons` can contain built-in action ids as strings or object references:

```json
[
  "cmux.newTerminal",
  "cmux.newBrowser",
  "cmux.splitRight",
  "cmux.splitDown",
  { "action": "custom-action-id" }
]
```

Use `ui.newWorkspace.contextMenu` for plus-button right-click menus. `ui.newWorkspace.rightClick` is accepted by cmux as a legacy alias, but new edits should use `contextMenu`.

## Workflow

### Step 1: Inspect current config

Read the existing config before changing anything.

```bash
cmux-settings dump --no-comments
```

If the user names a visible UI surface, search for the related ids.

```bash
rg -n "surfaceTabBar|newWorkspace|rightSidebar|<action-id>|<label>" ~/.config/cmux/cmux.json
```

### Step 2: Make the smallest config edit

Use the helper for global config edits. It parses JSONC and writes atomically.

Remove custom agent launch buttons from the surface tab bar while keeping built-in surface controls:

```bash
cmux-settings set ui.surfaceTabBar.buttons \
  '["cmux.newTerminal","cmux.newBrowser","cmux.splitRight","cmux.splitDown"]'
```

Remove one named action from a tab bar without deleting the action registry entry:

```bash
cmux-settings get ui.surfaceTabBar.buttons
# Edit the array to remove only { "action": "<action-id>" }, then set it back.
```

Delete an action entirely only when the user asks for the command itself to go away from every surface.

```bash
cmux-settings unset actions.<action-id>
```

Customize the plus button and its right-click menu:

```bash
cmux-settings set ui.newWorkspace.action '"workspace-new-cmux-worktree"'
cmux-settings set ui.newWorkspace.contextMenu \
  '[{"action":"workspace-new-cmux-worktree","title":"New cmux Worktree"},{"action":"workspace-terminal-browser","title":"Terminal + Browser"},{"type":"separator"},{"action":"cmux.newTerminal","title":"New Terminal"},{"action":"cmux.newBrowser","title":"New Browser"}]'
```

### Step 3: Verify

Always read back the changed path.

```bash
cmux-settings get ui.surfaceTabBar.buttons
cmux-settings get ui.newWorkspace.contextMenu
```

Validate parseability. The strict supported-key validator may flag valid structural or newer app keys when the checked-out source list is older than the running app. If that happens, do not remove unrelated keys. Confirm the file parses and report the unrelated validator warning.

```bash
cmux-settings dump --no-comments >/tmp/cmux-config.json
```

### Step 4: Report apply behavior

cmux watches `~/.config/cmux/cmux.json`, so config edits apply after save without a rebuild. Do not run a tagged app reload for pure config or skill changes.

## Rules

- Preserve unrelated custom actions, commands, menus, Vault entries, and right sidebar config.
- Do not delete action definitions just because their buttons were removed from the tab bar.
- Do not use `defaults write` for persistent product config.
- Do not edit `repo/` for user config changes.
- Do not run app reloads for config-only or skill-only changes.
- Keep responses short and include the exact path or key changed.
