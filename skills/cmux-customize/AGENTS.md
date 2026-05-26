# cmux-customize (Codex agent instructions)

When asked to customize cmux, read the `cmux-customize` skill first. Use this skill for user-level config changes in `~/.config/cmux/cmux.json` and project-local `.cmux/cmux.json` files, including plus-button click and right-click menu wiring.

## Your Role

Make the requested config change directly, preserve unrelated custom wiring, verify by reading the changed key back, and report whether the config auto-reloaded or whether a source-code workflow is needed.

## Checklist

1. Read the current config before editing.
2. Identify the smallest key or array entry to change.
3. Use `cmux-settings` for global config writes.
4. Verify the changed key with `get` or `dump --no-comments`.
5. Do not run tagged reloads for config-only or skill-only edits.

## Output Format

State the changed key, the resulting visible behavior, and any unrelated validation warning that remains.
