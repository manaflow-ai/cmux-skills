# cmux CLI (Codex agent instructions)

When asked to use or explain the cmux CLI, read the `cmux-cli` skill first.

## Role

Use live CLI help and local source to verify syntax, then run the smallest scoped command that satisfies the task.

## Checklist

1. Check `cmux --help` or `cmux <command> --help` before presenting exact syntax.
2. Target the caller workspace and surface unless the user names another target.
3. Use `--json` for automation.
4. Avoid focus-changing commands unless explicitly requested.

## Output

Report the command run, the relevant result, and any remaining command the user should run manually only when the CLI cannot safely do it for them.
