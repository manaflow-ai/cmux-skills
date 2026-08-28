# cmux Cloud command reference

All host-side commands go through the running cmux macOS app's socket; `cmux cloud` is an alias for `cmux vm`. Add `--json` for machine-readable output on commands that document it (interactive verbs like `shell`, `tui`, and `desktop` have none). Run `cmux vm <sub> --help` (or trigger the usage error with `cmux vm help`) to see the exact surface of the installed build, which is authoritative over this file.

## List and inspect

```bash
cmux vm ls                # NAME  LABEL  STATE  PROVIDER  IMAGE, plus a plan meter line
cmux vm status <id>       # provider, status, image (alias: info)
cmux vm stats <id>        # live CPU/memory usage (alias: top)
cmux vm tools <id>        # probe zsh/git/gh/htop/btop/node/bun/python3 inside the machine
cmux vm ports <id>        # listening TCP ports inside the machine (ss/netstat)
cmux vm handoff <id>      # one-screen summary with attach/inspect commands
cmux vm tree [<machine>|local] [--refresh]   # Finder-style catalog of every surface
```

Machine ids are generated names like `brave-otter`; the id is the address. `cmux vm ls` ends with the plan meter (`N of M machines on the <plan> plan`) and, on free plans, a countdown until free cloud access expires. `cmux vm tree` (same as `cmux surface ls`) lists This Mac plus every machine: its cmux-tui workspaces, terminals (title, cwd, agent state, whether a local pane already shows it), desktop, and forwarded ports — every line is an address `cmux vm open` (machine targets) or `cmux surface open` (any entry, including This Mac) accepts.

## Create

```bash
cmux vm new [--base] [--size <2g|4g|8g|16g|32g>] [--image <image-id>] \
            [--provider <blaxel|e2b|freestyle|daytona>] \
            [--workspace <workspace-id>] [--window <id|ref|index>] [--detach|-d]
```

- No positional arguments: `cmux vm new myvm` is rejected so a typo cannot silently provision a paid machine. Label it afterward with `cmux vm rename`.
- New machines boot the desktop image (xfce + noVNC) and open as terminal + desktop split. `--base` makes a shell-only machine on the backend default image.
- A bare `vm new` (no `--image`/`--provider` override) creates a persistent machine: the backend mounts a per-machine home volume, so each `vm new` mints a fresh durable machine up to the plan limit.
- The backend picks the provider (Blaxel by default); `--provider` is for deliberate rollback or experiments only.
- `--size` sets memory (vCPUs scale with it); plans cap the largest size.
- Without `--detach` the CLI attaches into a new workspace; with it, the machine id and next commands are printed.
- Create is idempotent against retries: a failed create can be re-run without double-provisioning.

```bash
cmux vm rename <id> <new-label>     # display label only; the id stays the address
cmux vm rename <id> --clear
```

## Base (the persistent cloud workspace slot)

```bash
cmux vm base                     # open Base, reuses the same VM (alias: base open)
cmux vm base open --detach       # ensure Base exists, print id, do not attach
cmux vm base reset [--reason <text>] [--detach]
```

Base is a single per-user persistent slot, pinned to the top of the sidebar. `reset` creates a new Base generation and retains the previous VM (its provider id is printed); nothing is destroyed.

## Attach and open

```bash
cmux vm shell <id>                       # terminal on the machine, as a workspace (alias: attach)
cmux vm tui <id>                         # the FULL cmux-tui client for the machine, in a pane
cmux vm desktop <id>                     # the machine's noVNC screen as a browser pane (alias: vnc)
cmux vm open <machine>                   # same as vm shell
cmux vm open <machine>/<workspace>       # a cmux-tui workspace on it (ws_… id or name)
cmux vm open <machine>/<ws>/<term>       # one terminal; focuses an existing pane showing it
cmux vm open <machine>:desktop           # the desktop
cmux vm open <machine>:port/<n>          # private tokened URL for an HTTP port, as a browser pane
cmux vm open <machine> <port> [--print]  # same; --print prints the URL instead of opening a pane
cmux vm ssh <id>                         # force plain SSH transport (degraded fallback)
cmux vm ssh-info <id>                    # print SSH host/port/user/credential info
```

`shell` uses the managed attach path: a short-lived lease to the machine's session daemon (cmux-tui on current images, cmuxd-remote WebSocket PTY on older ones); the transport depends on what the provider and image support. It survives reconnects, keeps scrollback on the machine, and is the same session primitive iOS uses. `ssh` forces the SSH fallback, which some providers and images cannot mint at all. `vm open` targets come from `cmux vm tree`. `--focus` defaults to false, so panes open beside the caller. See also `cmux surface open` / `cmux surface new-terminal` for the same catalog addressed as surfaces.

## Run commands

```bash
cmux vm exec <id> -- <command...>        # one command; argv is shell-quoted faithfully
cmux vm run [--sync] [--pull <remote-path>] [--machine <id>] [--new] \
            [--size <s>] [--timeout <seconds>] -- <command...>
cmux vm wait <id> [--timeout <seconds>] [--wake]
```

- `exec` waits about 35 seconds client-side and passes the remote exit code through. For longer work use `vm run` (default timeout 600s, max 15 minutes) or start a detached terminal via `vm agent` / `surface new-terminal`.
- `vm run` needs no machine name: it reuses an idle machine the router provisioned earlier (labeled `agent-pool` in `vm ls`), wakes a sleeping one, or provisions a fresh one. Hand-made machines are never drafted; pin one deliberately with `--machine`. `--sync` pushes the current directory to `work/<basename>` first; `--pull` fetches a path back afterward.
- `cmux vm route [--cwd <dir>] [--new] [--provision] [--size <s>]` prints which machine `vm run`/`vm agent` would pick and why, without running anything.
- `vm wait` blocks until the machine reports ready (running/ready/standby/paused); `--wake` also runs a trivial exec so a sleeping machine is awake on return.

## Coding agents on machines

```bash
cmux vm agent --agent <claude|codex|opencode|pi> [--machine <id>] [--sync] [--cwd <dir>] \
              [--name <name>] [--no-open] [--new] [--size <s>] -- <prompt or args...>
```

Starts the agent as a detached terminal in the machine's cmux-tui session: it keeps running when the pane closes and reattaches from any device with `cmux vm open <machine>/<ws>/<term>`. A bare prompt runs the agent's one-shot form (`claude -p`, `codex exec`, `opencode run`, `pi -p`); arguments starting with a flag or known subcommand pass through verbatim. Machine choice follows the `vm run` router unless `--machine` pins one.

## Files

```bash
cmux vm push <id> <local-path> [remote-path] [--exclude <pattern>]... [--no-default-excludes]
cmux vm pull <id> <remote-path> [local-path]
```

Copies over the exec channel, no SSH needed. Directories travel as tarballs with default excludes (node_modules, .git, and similar); transfers are size-capped, so ship repos without build artifacts. Remote paths default to the machine user's home.

## Snapshot, fork, restore

```bash
cmux vm snapshot <id> [--name <name>]         # alias: checkpoint; prints snapshot id
cmux vm fork <id> [--name <name>] [--detach]  # copy of a running machine
cmux vm restore <snapshot-id> [--provider <p>] [--detach]
cmux vm promote-template <id>                 # snapshot under a generated template-… name
```

Fork is provider-native where supported and otherwise snapshot-then-restore; the output says which (`snapshot: <id>` vs `native fork`).

## Destroy

```bash
cmux vm rm <id>        # aliases: destroy, delete
```

Irreversible and unprompted. Snapshot first when any state matters. Never destroy a machine you did not create in this session without the user's say-so; use `vm base reset` (which retains the old VM) when the user wants a fresh Base.

## Credentials for agents in the cloud

```bash
cmux ai-accounts list [--team <id>]
cmux ai-accounts upload <claude|codex|anthropic-key|openai-key> [--label <s>] [--validate]
cmux ai-accounts remove <account-id>
```

Uploads local AI credentials (Claude/Codex OAuth read from disk by the app; API keys read from `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`) to the team's model-routing tenant so coding agents inside cloud machines can authenticate. Prefer the env-var path over `--key`, which leaks the secret into shell history.

## Internal plumbing (do not call directly)

`cmux vm ssh-attach`, `cmux vm-pty-attach`, `cmux vm-ssh-attach`, `cmux vm-pty-connect`, `cmux vm-tui-connect`, and `cmux vm-tui-approve` are helpers the app runs inside managed attach panes. Use `cmux vm shell` / `cmux vm tui` / `cmux vm open` instead.
