---
name: cmux-groups
description: "Manage cmux sidebar workspace groups via the CLI and ~/.config/cmux/cmux.json. Trigger on workspace group, group sidebar, tab group, anchor workspace, cmux workspace group, cmux workspace-group, or any cmux.json workspaceGroups key."
---

# cmux workspace groups

Workspace groups are collapsible named sections in the cmux sidebar. Each group is owned by an anchor workspace. The group header is the anchor's sidebar representation, so there is no separate row for the anchor. Closing the anchor dissolves the group while preserving the other members as ungrouped workspaces.

## CLI

Prefer the canonical noun form:

```
cmux workspace group list [--json]
cmux workspace group create --name <name> [--cwd <path>] [--from <id>,<id>]
cmux workspace group ungroup <group-id>
cmux workspace group delete <group-id>
cmux workspace group rename <group-id> --name <new>
cmux workspace group collapse <group-id>
cmux workspace group expand <group-id>
cmux workspace group pin <group-id>
cmux workspace group unpin <group-id>
cmux workspace group add --group <group-id> --workspace <workspace-id>
cmux workspace group remove --workspace <workspace-id>
cmux workspace group set-anchor --group <group-id> --workspace <workspace-id>
cmux workspace group new-workspace <group-id> [--placement afterCurrent|top|end]
cmux workspace group set-color <group-id> [--hex #RRGGBB]
cmux workspace group set-icon <group-id> [--symbol <sf-symbol>]
cmux workspace group move <group-id> --to-index <n> | --before <group-id> | --after <group-id>
cmux workspace group focus <group-id>
```

`cmux workspace-group ...` is a compatibility alias for the same operations. `<group-id>` accepts UUIDs or refs such as `workspace_group:1`. All commands honor `--json`.

`create` inserts a fresh anchor workspace. It does not promote an existing workspace into the anchor. `--from` lists workspaces that become children under the new anchor. When `--from` is omitted, cmux uses the active sidebar selection or caller workspace when available.

`ungroup` dissolves a group while keeping every member workspace alive, including the anchor, which becomes a regular ungrouped workspace. `delete` is destructive and closes every workspace in the group.

`new-workspace` runs the group's new-workspace behavior: a new workspace is created at the anchor cwd and joined to the group. Placement can be passed explicitly, resolved from per-cwd config, or resolved from the global group default.

## Socket methods

The CLI is a thin wrapper over the v2 JSON socket API. Anything callable via CLI is also callable directly:

```
workspace.group.list
workspace.group.create        { name, cwd?, child_workspace_ids? }
workspace.group.ungroup       { group_id }
workspace.group.delete        { group_id }
workspace.group.rename        { group_id, name }
workspace.group.collapse      { group_id }
workspace.group.expand        { group_id }
workspace.group.pin           { group_id }
workspace.group.unpin         { group_id }
workspace.group.add           { group_id, workspace_id }
workspace.group.remove        { workspace_id }
workspace.group.set_anchor    { group_id, workspace_id }
workspace.group.new_workspace { group_id, placement? }
workspace.group.set_color     { group_id, hex? }
workspace.group.set_icon      { group_id, symbol? }
workspace.group.move          { group_id, to_index? | before_group_id? | after_group_id? }
workspace.group.focus         { group_id }
```

All accept the standard `window_id` / `window_ref` parameter to target a non-focused window.

## Configuration (`~/.config/cmux/cmux.json`)

Per-group settings are keyed by the anchor cwd. Keys with `*` or `?` are fnmatch globs with `~` expansion. Other keys are path prefixes. Longest match wins.

```json
{
  "workspaceGroups": {
    "newWorkspacePlacement": "afterCurrent",
    "byCwd": {
      "/abs/path/to/repo": {
        "color": "#7A4FD8",
        "icon": "ladybug.fill",
        "newWorkspacePlacement": "top",
        "contextMenu": [
          { "action": "newWorktreeAction", "title": "New Worktree" },
          { "action": "newWorkspace" }
        ]
      },
      "~/projects/*": {
        "icon": "leaf.fill",
        "newWorkspacePlacement": "end"
      }
    }
  }
}
```

`workspaceGroups.newWorkspacePlacement` and `workspaceGroups.byCwd[...].newWorkspacePlacement` accept:

- `afterCurrent`: after the active in-group workspace. It falls back to top when there is no active member reference.
- `top`: second slot, right after the anchor.
- `end`: after the last member.

Resolution order for group new-workspace placement:

1. Explicit `--placement afterCurrent|top|end` on the CLI, or `"placement"` in `workspace.group.new_workspace`.
2. Per-cwd `workspaceGroups.byCwd[...].newWorkspacePlacement`.
3. Global `workspaceGroups.newWorkspacePlacement`.
4. Built-in default `afterCurrent`.

Cmd-N inside a group uses the active group workspace as the placement reference. The group header `+` button and CLI path use the anchor as the reference, so `afterCurrent` behaves like `top` there.

Group context-menu items use the same schema as `ui.newWorkspace.contextMenu`; actions must be defined in the global `actions` block or be built-in actions such as `newWorkspace`.

## Keyboard

Default shortcut: Cmd-Shift-G groups the sidebar-selected workspaces. It falls back to the focused workspace when no sidebar selection exists. Rebind it in Settings > Keyboard.

## Anchor semantics

- Anchor identity lives on the group (`anchorWorkspaceId`), not as a flag on the workspace.
- The anchor renders as the group header, with no separate sidebar row.
- Closing the anchor dissolves the group after a confirm dialog.
- `set-anchor` reassigns which member is the anchor; the previously-anchor workspace becomes a regular member with its own sidebar row.

## Persistence

Groups and membership round-trip through `~/Library/Application Support/cmux/session-<bundle-id>.json` via the existing `SessionPersistenceStore`. Atomic rename-into-place writes; no WAL.

## Rules

- Prefer CLI or socket operations over editing session JSON.
- Do not write unsupported future config keys. Check `web/data/cmux.schema.json` in cmux when unsure.
- Preserve anchor semantics when scripting: moving a group means moving the anchor section, not only a child workspace row.
- Use `ungroup` when workspaces should survive; use `delete` only when every workspace in the group should close.
