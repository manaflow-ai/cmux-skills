---
name: cmux-freestyle
description: "Set up the cmux<>Freestyle integration by building a Freestyle VM snapshot that matches the cmux Cloud VM image. Use when the user asks to bring up cmux Cloud VMs on their own Freestyle account, mint a self-serve FREESTYLE_SANDBOX_SNAPSHOT, build a cmuxd-remote Freestyle snapshot from scratch, run the standalone cmux-freestyle setup script, or iterate on the manaflow-ai/cmux-freestyle repo."
---

# cmux Freestyle

Use this skill when a user wants a Freestyle VM snapshot that the cmux backend can boot Cloud VMs from. It lives in its own public repo, [`manaflow-ai/cmux-freestyle`](https://github.com/manaflow-ai/cmux-freestyle), so anyone with a Freestyle API key can run one shell script and get back a `FREESTYLE_SANDBOX_SNAPSHOT` id.

**Freestyle snapshots are scoped to the account that created them.** A snapshot id from manaflow's account, or from any other user, will not work for a different Freestyle account. Every user has to run the setup script against their own `FREESTYLE_API_KEY`. There is no shortcut.

## When to use

- User asks how to point their own cmux at Freestyle.
- User self-hosts the cmux web backend and needs a snapshot pinned to a known cmux release.
- User wants to rebuild the cmux Cloud VM image on their own Freestyle account.
- User wants to iterate on the standalone repo (`cmux-freestyle`) instead of the in-repo builder at `repo/web/scripts/build-cloud-vm-images.ts`.

For internal cmux development that pushes a new snapshot to manaflow's Freestyle account and updates `repo/web/services/vms/images/manifest.json`, keep using `repo/web/scripts/build-cloud-vm-images.ts`. This skill is the external-user path.

## What it builds

A Freestyle snapshot from a `Dockerfile` that mirrors `freestyleBaseDockerfileContent` in the in-repo builder:

- `ubuntu:24.04`, `C.UTF-8`, the same shell package set, the Python/OpenSSL shim required by the cmux browser proxy.
- `cmuxd-remote` Linux/amd64 downloaded from a pinned `manaflow-ai/cmux` GitHub release, SHA-256 verified during the image build against `cmuxd-remote-checksums.txt`.
- `/usr/local/bin/cmux` symlinked to `cmuxd-remote`.
- Node.js, Bun, plus pinned coding agent CLIs (Claude Code, OpenCode, Codex, Pi).
- Linux user `cmux` with passwordless sudo.
- Systemd unit `cmuxd-ws.service` running `cmuxd-remote serve --ws --listen 0.0.0.0:7777 --auth-lease-file ... --rpc-auth-lease-file ...` on Freestyle port `443 -> 7777`.

The image runs the same smoke tests as the in-repo builder, so failures show up at snapshot build time, not later inside a live VM.

## How to use it

The repo is self-contained; no cmux checkout required.

```bash
git clone https://github.com/manaflow-ai/cmux-freestyle.git
cd cmux-freestyle
export FREESTYLE_API_KEY=fk_...
./setup.sh
```

Or the one-liner:

```bash
FREESTYLE_API_KEY=fk_... \
  curl -fsSL https://raw.githubusercontent.com/manaflow-ai/cmux-freestyle/main/install.sh | bash
```

Useful flags / env on `./setup.sh snapshot` (the default subcommand):

- `--release <tag>` or `CMUX_RELEASE_TAG=<tag>` pins the cmuxd-remote release. Default is the latest stable `manaflow-ai/cmux` release.
- `--name <name>` or `CMUX_FREESTYLE_SNAPSHOT_NAME` sets the Freestyle snapshot name.
- `--skip-cache` or `CMUX_FREESTYLE_SKIP_CACHE=1` forces a clean Freestyle rebuild.
- `--codex-spec none`, `--claude-spec none`, etc. drop individual agent CLIs.
- `--json` emits a machine-readable result; the human path prints `FREESTYLE_SANDBOX_SNAPSHOT=sh-...` at the end.

The build takes 5 to 15 minutes depending on Freestyle's layer cache.

## Full self-host bundle

`./setup.sh` is a dispatcher with four subcommands. Use them together when a user wants more than just the snapshot id:

```bash
./setup.sh doctor                         # validate tools, env, Freestyle key, GitHub release
./setup.sh                                # mint a snapshot under the user's Freestyle account
./setup.sh web --snapshot sh-xxxxxx       # clone manaflow-ai/cmux, write web/.env.local, start Docker Postgres
./setup.sh home --ref feat-ink-rewrite    # install cmux-home (Ink TUI) headquarters view
```

`web` is the Next.js dev env bootstrap: it clones `manaflow-ai/cmux` to `~/cmux-freestyle-cmux`, writes the Freestyle + Cloud VM env keys into `web/.env.local`, runs `bun install`, and brings up the per-worktree Docker Postgres unless `--no-postgres` is set. Stack Auth keys (`STACK_SECRET_SERVER_KEY`, `NEXT_PUBLIC_STACK_PROJECT_ID`, `NEXT_PUBLIC_STACK_PUBLISHABLE_CLIENT_KEY`) are honoured if exported but optional. The script only needs `git` and `bun` (plus `docker` for Postgres).

`home` is the "headquarters view": it installs and prepares the Ink/TypeScript port of `cmux-home` at `~/cmux-freestyle-home/ink`. The TUI connects to the local cmux app's Unix socket and gives end users a Node-only dashboard of every workspace plus a Codex/Claude composer. The Ink port currently lives on the `feat-ink-rewrite` branch; switch the default `--ref` once it merges to `main`. The Rust crate at the cmux-home repo root remains the full-featured upstream.

If `FREESTYLE_API_KEY` is set in the env when `bun dev` runs (the `home` script exports it from the user's `~/.secrets/cmux.env` and the shell), cmux-home renders a second panel under the workspace list titled `Freestyle VMs (N)`. Each row shows the VM id, state, snapshot id (the one from `./setup.sh snapshot`), and age. This makes the TUI a single dashboard for both local cmux workspaces and the user's Freestyle Cloud VMs, with the same selection cursor walking both panels.

Selecting a VM enables the following actions on the row:

- `enter` opens the **sandbox** workflow: creates a new cmux workspace running `freestyle-vm-ssh <vmId>`. The helper script mints a short-lived Freestyle SSH identity, opens an SSH session through `vm-ssh.freestyle.sh` with `-R 31415:127.0.0.1:31415` (reverse-forward to the local [Subrouter](https://github.com/manaflow-ai/subrouter) AI gateway on `127.0.0.1:31415`) plus `-L` forwards for common dev ports (`3000`, `5173`, `8000`, `8080`), writes a `~/.codex/config.toml` inside the VM that points `openai_base_url` at the forwarded subrouter, then drops into a login shell. Codex launched inside the VM in that shell routes through Subrouter on the user's mac. Also opens a browser pane on the right at `http://127.0.0.1:3000`.
- `ctrl+o` opens the **local-codex** workflow: a normal cmux workspace at the TUI's `--cwd`, no SSH, plus a browser pane on the right at `https://<vmId>.vm.freestyle.sh`. Codex/Claude run on the mac against the local checkout; the VM is treated as a remote dev server.
- `ctrl+x` destroys the VM through the Freestyle SDK.
- `ctrl+n` on the `Freestyle VMs (N)` header creates a new VM from `FREESTYLE_SANDBOX_SNAPSHOT`.

**Freestyle gateway constraint.** The Freestyle SSH gateway at `vm-ssh.freestyle.sh` rejects `-R` remote port forwarding (`remote port forwarding failed for listen port 31415`). The `--reverse-subrouter` flag is therefore opt-in and works only for ordinary Linux/macOS sshd hosts.

**Default path for codex inside a Freestyle VM (works today)**: `freestyle-vm-ssh` mints an ephemeral preauth Tailscale key via `tsadmin api POST /tailnet/-/keys` (tag `tag:server`, expires in 1h), runs `tailscale up` inside the VM under userspace networking (`--tun=userspace-networking`), enables tailscaled's HTTP proxy + SOCKS5 server on `127.0.0.1:1055`, writes `/etc/profile.d/cmux-tailnet-proxy.sh` so every login shell exports `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`, and writes `~/.codex/config.toml` with `openai_base_url = "http://subrouter-team.tail41290.ts.net:31415/v1"`. Codex inside the VM then connects to the existing `subrouter-team` host on the tailnet through the local proxy, so all OpenAI traffic is routed through Subrouter's account scheduling. The cmux-freestyle snapshot already ships the apt `tailscale` package, so first-time bring-up is ~6 s end-to-end; subsequent sessions reuse the existing state.

Disable per-call with `--no-tailscale`, override the subrouter URL with `--subrouter-url <url>` or `SUBROUTER_REMOTE_URL`, override the auth-key with `--tailscale-authkey <key>` or `TAILSCALE_AUTHKEY`. Today Subrouter only routes Codex, so use Codex inside the VM until Subrouter adds Claude/OpenCode support.

Helper requires `sshpass` on the mac (`brew install hudochenkov/sshpass/sshpass`) and `tsadmin` on `PATH` (`skills/tsadmin/scripts/tsadmin`).

## GitHub auth

The snapshot builder talks only to public GitHub endpoints (`/repos/manaflow-ai/cmux/releases/latest` and the release-asset `cmuxd-remote-checksums.txt`). The unauthenticated GitHub API allows 60 requests per hour, which is fine in normal use. If a user hits a 403/429 (shared IP, CI loops, repeated rebuilds), they should set `GITHUB_TOKEN` (or `GH_TOKEN`) and the script forwards it on both the API call and the checksums download. Mention this when guiding a CI integration.

The Freestyle SDK only needs `FREESTYLE_API_KEY`; no GitHub credentials are required for snapshot creation. `setup.sh web` clones `manaflow-ai/cmux` anonymously, so no auth is required there either; only suggest `gh auth login` if a user explicitly wants `git push` against their own fork.

## Plugging the snapshot into cmux

After the script prints the snapshot id, hand the user the env block for their cmux backend:

```bash
FREESTYLE_API_KEY=fk_...
FREESTYLE_SANDBOX_SNAPSHOT=sh-xxxxxxxxxxxxxxxxxxxx
CMUX_VM_DEFAULT_PROVIDER=freestyle
CMUX_VM_FREESTYLE_ENABLED=1
```

The `FREESTYLE_API_KEY` and `FREESTYLE_SANDBOX_SNAPSHOT` must come from the same Freestyle account. Snapshot ids from other accounts will fail to boot.

For ad-hoc smoke testing:

```bash
npx -y freestyle vm create --snapshot <snapshotId> --ssh
```

Inside the VM, confirm everything baked correctly:

```bash
cmuxd-remote version
cmux --help
claude --version
codex --version
node --version
bun --version
```

## Iterating on the repo

The whole builder is one TypeScript file at `scripts/build-snapshot.ts`. When updating it, keep it in lockstep with the source of truth in `repo/web/scripts/build-cloud-vm-images.ts`:

- Pinned agent CLI versions (`CLOUD_AGENT_TOOLS`).
- Default Node major and Bun version.
- Dockerfile body (`freestyleBaseDockerfileContent`, `pythonOpenSSLCommands`, `toolInstallCommands`, `rootSetupCommands`, `imageSmokeTestCommands`).
- Snapshot create call shape and recovery behavior (`waitForFreestyleSnapshotByName`).

When cmux changes any of those, bump the matching constant in `cmux-freestyle`, ship a release, and update the cmux release tag the script defaults to if anything in the URL/checksum contract changes.

The Freestyle CLI (`npx -y freestyle vm ...`) covers VM create / list / ssh / exec / delete but does not expose snapshot create. That's why this script uses the `freestyle` SDK directly. Do not try to replace it with a CLI-only shell script.

## Rules

- Do not promise users that a shared snapshot id will work for them. It will not. Every user runs `./setup.sh` once with their own Freestyle API key.
- Do not bake provider API keys, R2 credentials, or anything user-specific into the snapshot. The Dockerfile must stay reproducible from public inputs only.
- Do not point the snapshot at an unreleased cmuxd-remote. Use a published `manaflow-ai/cmux` release tag so SHA-256 verification has something to anchor on.
- Do not loosen the agent CLI version policy. Specs must be exact semver pins; ranges and `latest` are rejected on purpose so each rebuild is reproducible.
- Do not run this against the manaflow Freestyle account when iterating. Use a personal Freestyle account; manaflow's snapshot lifecycle is managed by the in-repo builder and the cmux image manifest.
