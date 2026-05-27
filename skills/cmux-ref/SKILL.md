---
name: cmux-ref
description: "Interpret pasted cmux workspace, pane, surface, or window refs and IDs. Use for cmux-ref, cmux-id, workspace_ref, workspace_id, pane_ref, pane_id, surface_ref, surface_id, window_ref, or window_id context blocks."
---

# cmux Ref

Use this skill when the user pastes cmux topology identifiers and expects the agent to target that exact workspace, pane, surface, or window. Treat those identifiers as explicit routing context for later instructions.

## What To Recognize

Users may paste any mix of these fields, in plain text, Markdown, JSON, YAML, shell-style assignments, or logs:

```text
workspace_ref=workspace:1
workspace_id=D9C23F06-55C8-4EF6-96D2-F2531B3327A8
pane_ref=pane:2
pane_id=60495E4A-56E3-469D-A274-A7877F48B54D
surface_ref=surface:370
surface_id=661B301A-2423-44F1-B789-7AEA1021CFCE
```

Recognize these keys:

- `window_ref`, `window_id`
- `workspace_ref`, `workspace_id`
- `pane_ref`, `pane_id`
- `surface_ref`, `surface_id`

Also recognize bare refs near user intent, such as `workspace:1`, `pane:2`, or `surface:370`.

## Meaning

- `*_ref` values are short cmux refs such as `workspace:1`, `pane:2`, and `surface:370`. They are convenient for immediate CLI calls in the same cmux instance, but can be renumbered after state changes.
- `*_id` values are UUIDs for the same objects. Prefer them for identity checks and stale-ref recovery when both forms are available.
- The most specific provided object is the default target: `surface` beats `pane`, `pane` beats `workspace`, and `workspace` beats `window`.
- A complete block describes a hierarchy. Do not mix a `surface_id` from one pasted block with a `workspace_ref` from another unless the user clearly says they belong together.

## Workflow

### Step 1: Parse The Block

Extract keys case-insensitively. Accept `=` or `:` separators and ignore quotes, commas, and code fences.

Useful pattern:

```text
\b(window|workspace|pane|surface)_(ref|id)\b\s*[:=]\s*["']?([A-Za-z0-9:-]+)["']?
```

If the user provides only bare refs, bind the most specific one as the target:

```text
workspace:1 pane:2 surface:370
```

### Step 2: Announce The Target

When taking action, say the exact target briefly:

```text
I will target surface:370 in pane:2, workspace:1.
```

If a UUID is present, keep it in your internal target record and include it when useful for disambiguation:

```text
I will target surface:370 (661B301A-2423-44F1-B789-7AEA1021CFCE).
```

### Step 3: Verify Before Mutating

Before sending text, closing anything, moving surfaces, changing layout, or reading a screen for a non-current target, verify the target exists in the active cmux socket.

Use the current cmux CLI and request both refs and UUIDs:

```bash
cmux --json --id-format both tree --all
cmux --json --id-format both identify
cmux --json --id-format both list-pane-surfaces --workspace <workspace_ref_or_id>
```

If a ref is stale but the UUID exists in `tree --all`, use the current ref associated with that UUID. If neither the ref nor UUID can be found, stop and ask the user for a fresh cmux ref block.

### Step 4: Use Explicit Targets

Do not fall back to the visually focused workspace when the user pasted explicit refs. Pass the parsed workspace, pane, and surface to cmux commands.

Examples:

```bash
cmux read-screen --workspace workspace:1 --surface surface:370 --scrollback --lines 120
cmux send --workspace workspace:1 --surface surface:370 "npm test\n"
cmux new-surface --workspace workspace:1 --pane pane:2 --type terminal --focus false
cmux open ./report.html --workspace workspace:1 --pane pane:2 --no-focus
```

If the command accepts only one handle, use the most specific relevant handle. Prefer the UUID when the command accepts UUIDs and you have verified it maps to the intended object.

## Ambiguity Rules

Ask one concise question only when the target cannot be inferred safely:

- Multiple unrelated ref blocks are pasted and the instruction says only "use this" or "that one".
- A workspace ref and surface ref are both present but verification shows they belong to different current hierarchies.
- The pasted identifiers are stale and no UUID match exists in `cmux --json --id-format both tree --all`.

Do not ask when one complete block is present. Use the most specific target in that block.

## Safety Rules

- User-provided cmux refs override caller environment variables and visual focus.
- Preserve both the ref and UUID in notes or scripts when available.
- Do not change focus just to verify or use a target. Prefer non-disruptive commands and `--focus false` or `--no-focus` when supported.
- Do not close, move, or send input to a target until it has been verified in the current socket.
- Browser snapshot element refs are separate from cmux topology refs. Use `cmux-browser` for DOM or webview snapshot refs.
