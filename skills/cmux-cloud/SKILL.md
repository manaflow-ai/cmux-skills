---
name: cmux-cloud
description: "Use cmux Cloud machines through the CLI. Use when the user says cmux cloud, cloud VM, cloud machine, cmux vm, Base workspace, machines panel, run/exec on a cloud machine, cloud agent, vm snapshot/fork/restore, push/pull files to a VM, open a port or desktop on a machine, or notify from inside a VM."
---

# cmux Cloud

Drive cmux Cloud machines (user-owned persistent Linux VMs) through the `cmux` CLI: create and attach, run commands and coding agents, move files, open ports and desktops, snapshot/fork/restore, and send notifications from inside a machine. Full per-command syntax lives in `references/commands.md`; `cmux vm <sub> --help` on the installed build is authoritative when they disagree.

## Mental model

- A **machine** is a persistent cloud VM owned by the signed-in cmux user. Its generated name (`brave-otter`) is its address everywhere; `cmux vm rename` sets a display label only. The cloud backend picks the provider; the machine outlives your panes, your Mac being closed, and reconnects.
- Every machine runs a **cmux session daemon** (cmux-tui on current images, cmuxd-remote on older ones) that owns terminal sessions and scrollback. Clients (Mac panes, iOS) attach through short-lived leases minted by the backend; the transport depends on what the provider and image support. SSH is a fallback some providers and images cannot mint at all, and its absence is not an error.
- New machines boot a **desktop image** (xfce + noVNC) plus a shell, with a persistent per-machine home. `--base` gives a shell-only machine.
- **Base** is a separate single per-user persistent slot, pinned to the top of the sidebar. `vm new` mints fresh machines; `vm base` always reopens the same one.
- Terminals on a machine live in its **cmux-tui session** (workspaces `ws_…`, terminals `term_…`). They keep running detached; `cmux vm tree` catalogs every surface (local and cloud) and every line is an address `cmux vm open` (machine targets) or `cmux surface open` (any entry, including This Mac) accepts, e.g. `brave-otter/main/term_2f9c…`, `brave-otter:desktop`, `brave-otter:port/3000`.
- **Pool machines** (labeled `agent-pool` in `vm ls`) are provisioned by the `vm run`/`vm agent` router and reused for routed work. The router never drafts machines a person made by hand.
- Plans cap active machine count and memory. `cmux vm ls` prints the meter (`N of M machines on the <plan> plan`) and, on free plans, when free cloud access expires.

## Prerequisites

Host-side commands go through the running cmux macOS app's socket: the app must be running and signed in (machines belong to that account/team). `cmux --version`, `cmux ping`, then `cmux vm ls` is the fastest health check. Commands that document `--json` support it for scripting. Creating machines costs money and counts against the plan; prefer reuse over creation.

## Workflows

### Run a one-off command

```bash
cmux vm run -- uname -a                       # router picks/wakes/creates a pool machine
cmux vm run --sync -- bun test                # push current dir to work/<basename> first
cmux vm run --sync --pull work/app/dist -- sh -c 'cd work/app && bun run build'
cmux vm exec <id> -- pwd                      # when you already know the machine
```

`exec` gives up after ~35s client-side; `vm run` allows up to 15 minutes. For anything longer, start a detached terminal (`vm agent`, or `cmux surface new-terminal --machine <id> -- <command...>`) and check on it via `vm tree` / `vm open`.

### Run a coding agent in the cloud

```bash
cmux vm agent --agent claude --sync -- "run the test suite and fix failures"
cmux vm agent --agent codex --machine brave-otter -- exec "summarize work/app"
```

Agents (`claude`, `codex`, `opencode`, `pi` are preinstalled) start as detached terminals in the machine's cmux-tui session: closing the pane does not kill them, and `cmux vm open <machine>/<ws>/<term>` reattaches from any device. Credentials for cloud agents come from `cmux ai-accounts upload`.

### Create, attach, inspect

```bash
cmux vm new --detach                # fresh persistent machine; prints id + next commands
cmux vm shell <id>                  # terminal workspace on it (managed attach)
cmux vm desktop <id>                # its noVNC screen as a browser pane
cmux vm tui <id>                    # the machine's full cmux-tui client in a pane
cmux vm base                        # the persistent Base slot
cmux vm status <id>; cmux vm stats <id>; cmux vm ports <id>; cmux vm tools <id>
```

### Preview a server running on a machine

```bash
cmux vm open <id> 3000              # private tokened URL, opened as a browser pane
cmux vm open <id> 3000 --print      # just print the URL
```

### Move files

```bash
cmux vm push <id> ./myrepo work/myrepo      # dirs travel as tarballs, node_modules/.git excluded
cmux vm pull <id> work/report.pdf
```

### Save and reproduce state

```bash
cmux vm snapshot <id> --name before-upgrade
cmux vm restore <snapshot-id>               # new machine from the snapshot
cmux vm fork <id>                           # copy of a running machine
```

## Inside a machine

The guest `cmux` binary is the machine's relay CLI. Its commands are forwarded to the **connected cmux app on the user's Mac**, not executed in the VM: `cmux notify` posts to the user's notification center, `cmux browser …` drives the Mac's browser panes, `cmux read-screen` / `send` / workspace and pane verbs act on the Mac's UI. It resolves its socket from `CMUX_SOCKET_PATH`, then `~/.cmux/socket_addr`, then the cloud CLI bridge socket; if no client is attached, relay commands fail — that is expected, not a broken install.

The one every cloud agent should know:

```bash
cmux notify --title "Build done" --subtitle "myrepo" --body "Tests green, artifact in work/dist"
```

`--workspace`/`--surface` default from `CMUX_WORKSPACE_ID`/`CMUX_SURFACE_ID` so the notification is attributed to the calling pane. Agent tool paths live under `/root/.npm-global/bin`, `/root/.bun/bin`, `/root/.local/bin`; use a login shell (`bash -lc`) when a tool is "missing".

## Rules

- MUST NOT run `cmux vm rm` on a machine you did not create in this session unless the user names it this turn. It is irreversible and unprompted. When the user wants a fresh Base, use `cmux vm base reset`, which retains the old VM.
- MUST NOT pass a name to `cmux vm new` — it takes no positional arguments (rejected to prevent accidental paid provisioning). Create, then `cmux vm rename`.
- Prefer `vm run`/`vm agent` routing over creating machines; creation counts against the plan limit and bills the user. Check `cmux vm ls` before `vm new`.
- Do not loop on `vm status` waiting for readiness; use `cmux vm wait <id> [--wake]`.
- Do not use `cmux vm ssh` unless the managed attach path failed; some providers and images cannot mint SSH, so treat "SSH unavailable" as normal, not as an error to fix. Say why in the handoff when you fall back.
- Do not call the internal attach helpers (`vm ssh-attach`, `vm-pty-attach`, `vm-ssh-attach`, `vm-pty-connect`, `vm-tui-connect`, `vm-tui-approve`).
- `vm exec` quoting is faithful per argv element; do not pre-quote. Wrap shell constructs as `-- sh -c '<script>'`.
- Provider choice belongs to the backend. Use `--provider` only for a rollback or experiment the user asked for.
- Use `--json` only on commands whose `--help` documents it; interactive verbs (`shell`, `tui`, `desktop`) have none. Do not parse the human table output either way.
- Plan limits, sizes, and providers change; read them from `cmux vm ls` and `--help` output rather than assuming values from this file.
