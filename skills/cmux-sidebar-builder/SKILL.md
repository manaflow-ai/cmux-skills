---
name: cmux-sidebar-builder
description: "Build, inspect, or revise cmux left-sidebar custom views using the runtime SwiftUI-style interpreter. Use for custom sidebars, left sidebar building, sidebar vibe coding, interpreted Swift sidebars, ~/.config/cmux/sidebars/*.swift, cmux docs sidebars, or Aziz's Swift interpreter work."
---

# cmux sidebar builder

Use this skill when the task is to create or modify a cmux left-sidebar custom view. These are user/agent-authored `.swift` files in `~/.config/cmux/sidebars/` rendered by cmux's runtime SwiftUI-style interpreter, not compiled app code.

## Orientation

- The original work is PR `https://github.com/manaflow-ai/cmux/pull/5254` by Aziz Albahar.
- The feature is opt-in behind the UserDefaults-backed key `customSidebars.beta.enabled`.
- Custom sidebars live under `~/.config/cmux/sidebars/` and appear in the left sidebar picker when the beta is enabled.
- Start from the cmux app checkout docs: `repo/docs/custom-sidebars.md`.

Important cmux source entrypoints:

- `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/SwiftViewInterpreter.swift`
- `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/ExpressionEvaluator.swift`
- `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/RenderNode.swift`
- `repo/Packages/CmuxSwiftRenderUI/Sources/CmuxSwiftRenderUI/Sidebar/CustomSidebarView.swift`
- `repo/Sources/ContentView.swift`, around `customSidebarsDirectory`, `customSidebarDataContext`, and `CustomSidebarView(...)`.

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

- This is the left sidebar. Do not use right-sidebar configuration or ExtensionKit unless the user explicitly asks for that surface.
- Keep custom sidebar files small and inspectable. If a design gets complicated, split behavior into simple helper functions only if the interpreter supports them.
- Make every visible action explicit through supported `Button` action payloads. Do not invent action ids without checking `repo/Packages/CmuxSwiftRender/Sources/CmuxSwiftRender/ActionCommand.swift` and app dispatch wiring.
- Prefer real workspace, surface, notification, port, git, and progress fields from the cmux context. Avoid placeholder dashboards unless the task is only a mockup.
- When a rendering failure happens, reduce to the smallest sidebar file that reproduces it, then compare against `CmuxSwiftRender` tests and corpus examples.

## Verification

For config-only sidebars:

```bash
ls ~/.config/cmux/sidebars
cmux sidebar validate <name>
```

Do not change the user's selected/default sidebar as part of normal authoring. The original workspaces sidebar should remain the default unless the user explicitly asks to activate the custom sidebar.

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
