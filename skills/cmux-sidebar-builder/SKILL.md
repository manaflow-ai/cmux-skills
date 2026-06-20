---
name: cmux-sidebar-builder
description: "Build, inspect, or revise cmux custom sidebar views using the runtime SwiftUI-style interpreter. Use for sidebar vibe coding, custom sidebars in Bonsplit panes, left sidebar picker previews, interpreted Swift sidebars, ~/.config/cmux/sidebars/*.swift, cmux docs sidebars, or Aziz's Swift interpreter work."
---

# cmux sidebar builder

Use this skill when the task is to create or modify a cmux custom sidebar view. These are user/agent-authored `.swift` files in `~/.config/cmux/sidebars/` rendered by cmux's runtime SwiftUI-style interpreter, not compiled app code. The primary dogfood surface is a normal Bonsplit pane tab opened with `cmux sidebar open <name>`; the left sidebar picker remains useful for previews.

## Orientation

- The original work is PR `https://github.com/manaflow-ai/cmux/pull/5254` by Aziz Albahar.
- The feature is opt-in behind the UserDefaults-backed key `customSidebars.beta.enabled`.
- Custom sidebars live under `~/.config/cmux/sidebars/`. They can be opened as normal Bonsplit pane tabs with `cmux sidebar open <name>` and appear in the left sidebar picker when the beta is enabled.
- Start from the cmux app checkout docs: `repo/docs/custom-sidebars.md`.

Important cmux source entrypoints:

- `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/SwiftViewInterpreter.swift`
- `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/ExpressionEvaluator.swift`
- `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/RenderNode.swift`
- `repo/Packages/CmuxSwiftRenderUI/Sources/CmuxSwiftRenderUI/Sidebar/CustomSidebarView.swift`
- `repo/Sources/ContentView.swift`, around `customSidebarsDirectory`, `customSidebarDataContext`, and `CustomSidebarView(...)`.
- `repo/Sources/Panels/CustomSidebarPanel.swift` for the Bonsplit pane host.
- `repo/Sources/Workspace+CustomSidebarPane.swift` and `repo/Sources/TerminalController+CustomSidebarCommands.swift` for the `cmux sidebar open <name>` path.

Follow-up implementation branches to inspect when needed:

- `origin/feat-interpreter-primitives` for the broader supported SwiftUI-ish primitive surface.
- `origin/feat-sidebar-interpreter-isolation` for the out-of-process crash-isolated interpreter worker.

## Workflow

1. Inspect the current app docs and interpreter surface before authoring:
   ```bash
   sed -n '1,220p' repo/docs/custom-sidebars.md
   rg -n "struct SwiftViewInterpreter|func evaluate|func parse|enum RenderNode|customSidebarDataContext|customSidebarsDirectory" repo/Packages/CmuxSwiftRender repo/Packages/CmuxSwiftRenderUI repo/Sources/ContentView.swift
   ```

2. Create or edit the sidebar file in the user's config directory:
   ```bash
   mkdir -p ~/.config/cmux/sidebars
   $EDITOR ~/.config/cmux/sidebars/<name>.swift
   ```

3. Stay inside the interpreted subset. Prefer simple SwiftUI-style expressions: `VStack`, `HStack`, `Text`, `Image`, `Button`, `ForEach`, conditionals, supported modifiers, and data from the provided context. Do not assume arbitrary Swift, imports, async work, filesystem access, networking, custom types, or compiled dependencies are available.

4. Use the provided data context instead of shelling out. If the sidebar needs data that is not exposed, identify the missing field in `customSidebarDataContext` and treat adding it as an app code change in a cmux worktree.

5. If you change app/runtime code, follow the cmux repo workflow: create a worktree, read repo-local instructions, localize user-facing strings, test appropriately, and reload with a tag before dogfood handoff. Config-only sidebar `.swift` edits do not require an app rebuild.

## Authoring rules

- Do not use `cmux right-sidebar set <name>` or right-sidebar configuration for custom sidebars. Custom sidebars should render in a Bonsplit pane via `cmux sidebar open <name>` when the user wants to see the sidebar next to their work.
- The left sidebar picker is a preview/selection surface. Do not treat the right sidebar as a custom-sidebar host.
- Do not use ExtensionKit unless the user explicitly asks for that surface.
- Keep custom sidebar files small and inspectable. If a design gets complicated, split behavior into simple helper functions only if the interpreter supports them.
- Make every visible action explicit through supported `Button` action payloads. Do not invent action ids without checking `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/ActionCommand.swift` and app dispatch wiring.
- Prefer real workspace, surface, notification, port, git, and progress fields from the cmux context. Avoid placeholder dashboards unless the task is only a mockup.
- When a rendering failure happens, reduce to the smallest sidebar file that reproduces it, then compare against `CmuxSwiftRender` tests and corpus examples.

## Verification

For config-only sidebars:

```bash
ls ~/.config/cmux/sidebars
cmux sidebar validate <name>
cmux sidebar open <name>
```

Do not change the user's selected/default sidebar as part of normal authoring. The original workspaces sidebar should remain the default unless the user explicitly asks to activate the custom sidebar.

After opening, verify the custom sidebar is a pane surface, not the right sidebar:

```bash
cmux identify --json --id-format both
cmux tree --workspace <workspace-ref> --json --id-format both
cmux right-sidebar set <name>   # should fail on current builds; do not use this for setup
```

For tagged dogfood, use the tag-bound dev CLI and socket, for example `~/.local/bin/cmux-dev --socket /tmp/cmux-debug-<tag>.sock sidebar open <name> --json`, then verify the focused surface reports `surface_type: customSidebar`.

If the running cmux build supports it, reload valid custom sidebars without selecting one:

```bash
cmux sidebar reload --all
```

Editing a sidebar file alone should not be treated as a reload signal. Use the CLI reload command after writes are complete so half-written files do not replace a mounted sidebar.

Only when the user explicitly asks to activate the custom sidebar, validate and select it:

```bash
cmux sidebar select <name>
```

For older cmux builds without `cmux sidebar`, ask the user to pick the named sidebar from the left sidebar picker. Avoid `defaults write` for sidebar selection unless the user explicitly requests temporary local dogfood setup, and state that it is not a product default.

For interpreter or app changes, prefer focused package tests for `CmuxSwiftRender` plus the smallest real dogfood reload. Do not run local cmux `xcodebuild ... test`; use the project's remote or CI test guidance.
