# cmux-skills

Public skills for working with [cmux](https://github.com/manaflow-ai/cmux), a Ghostty-based macOS terminal with vertical tabs and notifications for AI coding agents.

Skills follow the [Agent Skills](https://agentskills.io/) format and work with any agent that supports the `.agents/skills/` or `.claude/skills/` conventions (Claude Code, Codex, Cursor, Amp, OpenCode, Goose, and more).

## Install

The easiest path is the [`skills`](https://skills.sh) CLI:

```bash
# Add only the cmux entry point (it falls back to live CLI help)
npx skills add manaflow-ai/cmux-skills -g --skill cmux

# Recommended: install the router and focused skills globally, then invoke only $cmux
npx skills add manaflow-ai/cmux-skills -g --all

# Or pick specific ones, for specific agents
npx skills add manaflow-ai/cmux-skills --skill cmux-cli cmux-config --agent claude-code

# List what's in the repo without installing
npx skills add manaflow-ai/cmux-skills --list
```

You can also clone the repo and symlink the skills you want into your agent's skills directory, e.g. `~/.claude/skills/` or `.agents/skills/`.

## Skills

| Skill | What it does |
|---|---|
| [`cmux`](skills/cmux) | Main entry point for `$cmux`. Explains cmux and routes workspace, browser, config, CLI, sidebar, artifact, and Cloud tasks to the right focused skill. |
| [`cmux-cli`](skills/cmux-cli) | Reference for the `cmux` CLI: socket commands, workspaces, panes, surfaces, browser, hooks, feed, settings, automation. |
| [`cmux-config`](skills/cmux-config) | Configure `~/.config/cmux/cmux.json`: typed settings (helper script that strips JSONC comments, writes atomically, validates keys), customization (tab bar buttons, plus-button menus, custom actions/commands, right sidebar), and sidebar workspace groups. |
| [`cmux-ref`](skills/cmux-ref) | Interpret pasted cmux workspace, pane, surface, and window refs or UUIDs as explicit target context. |
| [`cmux-sidebar-builder`](skills/cmux-sidebar-builder) | Build left-sidebar custom views with cmux's runtime SwiftUI-style interpreter. |
| [`cmux-workspace`](skills/cmux-workspace) | Work inside the current cmux workspace: caller surface, panes, surfaces, tagged reloads, socket targeting, non-interfering automation. |
| [`cmux-browser`](skills/cmux-browser) | Drive cmux browser surfaces: snapshot refs, DOM actions, waits, screenshots, cookies, storage, tabs, downloads, console, errors. |
| [`cmux-artifact`](skills/cmux-artifact) | Build durable HTML walkthrough artifacts for dogfood, verification, demos, and evidence pages, and open them in the current workspace. |
| [`cmux-cloud`](skills/cmux-cloud) | Use cmux Cloud machines through the `cmux vm` CLI: create, attach, Base, exec/run, cloud coding agents, file push/pull, ports and desktop, snapshot/fork/restore, and in-VM notifications. |
| [`cmux-freestyle`](skills/cmux-freestyle) | Bring up cmux Cloud VMs on your own Freestyle account by minting a `FREESTYLE_SANDBOX_SNAPSHOT`. |

## Layout

```
skills/
  cmux/SKILL.md
  cmux/references/overview.md
  cmux-artifact/SKILL.md
  cmux-browser/SKILL.md
  cmux-cli/SKILL.md
  cmux-config/SKILL.md
  cmux-config/references/{all-keys,shortcut-actions,customize,groups}.md
  cmux-config/scripts/cmux-settings
  cmux-cloud/SKILL.md
  cmux-cloud/references/commands.md
  cmux-freestyle/SKILL.md
  cmux-sidebar-builder/SKILL.md
  cmux-ref/SKILL.md
  cmux-workspace/SKILL.md
```

Each skill is a self-contained directory with a `SKILL.md` plus any helper scripts, references, or agent configs it needs.

## Contributing

Open an issue or PR at [manaflow-ai/cmux-skills](https://github.com/manaflow-ai/cmux-skills). The canonical source for cmux itself lives at [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux).

## License

MIT. See [LICENSE](LICENSE).
