---
name: cmux-artifact
description: "Create durable HTML walkthrough artifacts for cmux dogfood, verification, demos, evidence pages, artifact previews, and open helpful tabs or splits in the current cmux workspace."
---

# cmux Artifact

Use this skill when the user asks for an HTML artifact, walkthrough, evidence page, demo page, artifact preview, or a workspace layout that helps them dogfood, verify, or understand a change. The goal is a durable, inspectable artifact plus non-disruptive cmux workspace tabs for the important evidence.

## Prerequisites

- The caller cmux workspace is the default target, not a requirement. Read the `cmux-workspace` skill when opening panes, tabs, browsers, logs, screenshots, videos, or generated documents.
  - Default to the caller workspace's right helper pane for task-tied evidence (dogfood proof, failure logs, verification pages) that the user wants next to the work they triggered.
  - Prefer a dedicated or new workspace when the artifact is standalone and durable (a design doc, report, or reference page the user will return to), when splitting the caller workspace would crowd an active terminal, or when the user asks for it elsewhere. Create it additively with `cmux new-workspace`; only switch to it when the user asked to view the artifact now (an explicit "open it" counts). Never call `select-workspace`/`focus-pane` speculatively.
  - If unsure which fits, ask, or pick the least-disruptive option and say where you put it so the user can redirect.
- Prefer real command output, logs, screenshots, traces, and timings. Do not invent evidence.
- Keep final user-facing artifacts out of `/tmp`.

## Artifact Location

Put final artifacts under a branch-scoped durable tree:

```bash
BRANCH="$(git -C <worktree-or-repo> branch --show-current 2>/dev/null || echo task)"
ASSET_ROOT="/cmux-assets/${BRANCH:-task}/<artifact-slug>"
mkdir -p "$ASSET_ROOT"
```

If `/cmux-assets` cannot be created or written, use `cmux-assets/<branch>/<artifact-slug>` under the current repo checkout and state that fallback. `/tmp` is scratch only. Copy accepted logs, screenshots, frames, videos, and transcripts into the durable tree before opening or reporting them.

## Workflow

### Step 1: Gather Evidence

Collect the smallest set of real artifacts that explain the task:

- command transcript or terminal output
- relevant logs
- screenshots, frames, video, or browser snapshots
- timing table with exact durations
- code references or PR links when useful
- cleanup state and remaining blockers

Use concise names such as `run-transcript.md`, `server.log`, `failure.log`, `screenshot.png`, and `index.html`.

### Step 2: Write `index.html`

Create a standalone HTML document that works from the filesystem. Include:

- a plain-language summary of what was tested or changed
- a short timeline or step table
- key timings
- links to local copied logs/media using relative paths
- observed failures and the direct next action
- cleanup status if external resources were created

Use simple, dense UI suitable for engineering review. Avoid marketing sections, giant hero layouts, decorative gradients, or hidden evidence.

For interactive artifacts, it is OK to create a small React website instead of a single static document. Keep it under the same durable `ASSET_ROOT`, for example `package.json`, `server.ts`, `src/main.jsx`, `src/styles.css`, and `public/`. Prefer a no-install setup using existing repo dependencies or browser ESM imports. If `bun` is installed and hosting helps the user play with the UI, run a foreground Bun server in a visible cmux helper terminal, then open the exact local URL in a browser surface. Do not use hidden `tmux`, `nohup`, detached background servers, or generic localhost pages for hosted artifacts. If Bun is unavailable or hosting adds no value, fall back to a filesystem `index.html`.

### Step 3: Open Helpful Tabs

Open the final `index.html` as a browser surface navigated to its `file://` URL without changing focus. The target is the caller workspace's right helper pane by default, but it may be a dedicated or new workspace per the Prerequisites (standalone durable artifacts, or when splitting the caller workspace would crowd an active terminal). When you use a separate workspace, pass `--workspace <that-workspace>` to the surface/pane commands below instead of `${CMUX_WORKSPACE_ID}`. Do not open HTML artifacts with `cmux open`, because that creates a file preview instead of exercising the artifact in the browser. Open raw evidence such as logs, Markdown transcripts, screenshots, or videos with `cmux open` after the browser artifact is handled.

First check whether the same `index.html` artifact is already open in the target workspace or helper pane. If it is already open as a browser surface, keep that exact surface, navigate it to the artifact URL if needed, then always reload it after updating `index.html` before handoff:

```bash
FILE_URL="$(node -e 'const {pathToFileURL}=require("url"); console.log(pathToFileURL(process.argv[1]).href)' "$ASSET_ROOT/index.html")"
cmux browser --surface surface:<existing-artifact-browser> goto "$FILE_URL" --snapshot-after
cmux browser --surface surface:<existing-artifact-browser> reload --snapshot-after
```

Do not treat `goto` as enough after rewriting the same file. Browser surfaces can keep stale file content; `reload --snapshot-after` is the proof that the currently visible artifact was refreshed.

If the existing artifact is open as a file preview or another non-reloadable surface, close that exact stale artifact surface, then open one browser surface in the same helper pane. If there are duplicate surfaces for the same artifact, keep one browser surface if present, close stale duplicates, and navigate or reload the kept browser. Do not leave multiple `index.html` tabs for the same artifact because it makes the current version ambiguous.

**Put the artifact in its own pane, side by side with the work.** The point is evidence visible *next to* the terminal, not hidden behind it. If the caller workspace already has a suitable right helper pane, reuse it. If the workspace is a single pane (just the active terminal), do NOT add the artifact as another surface in that pane: `new-surface --pane <active-pane>` makes it a background tab stacked behind the terminal, so the user sees nothing change. Create a right split instead. Use `new-pane --direction right` to open the browser directly in a new right pane, or `split-off` a surface you already created in the active pane.

```bash
FILE_URL="$(node -e 'const {pathToFileURL}=require("url"); console.log(pathToFileURL(process.argv[1]).href)' "$ASSET_ROOT/index.html")"

# Single-pane workspace (no right helper yet): open the artifact in a NEW right split.
cmux new-pane --workspace "${CMUX_WORKSPACE_ID:-}" \
  --direction right \
  --type browser \
  --url "$FILE_URL" \
  --focus false

# Already have a dedicated right helper pane: add the browser surface there.
cmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" \
  --pane pane:<right-helper> \
  --type browser \
  --url "$FILE_URL" \
  --focus false

# Recovery: artifact landed as a background tab in the active terminal's pane?
# Split that exact surface out to the right instead of leaving it buried.
cmux split-off --surface surface:<artifact-browser> right --focus false

cmux open "$ASSET_ROOT/failure.log" \
  --workspace "${CMUX_WORKSPACE_ID:-}" \
  --pane pane:<right-helper> \
  --no-focus
```

For hosted React artifacts, create or reuse a helper terminal in the same target workspace/pane, run the server there, verify it is visibly running, then open the served URL:

```bash
cmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" \
  --pane pane:<right-helper> \
  --type terminal \
  --focus false
cmux send --surface surface:<helper-terminal> \
  "cd '$ASSET_ROOT' && PORT=<port> bun run server.ts\n"
curl -fsS "http://127.0.0.1:<port>/healthz"
cmux new-surface --workspace "${CMUX_WORKSPACE_ID:-}" \
  --pane pane:<right-helper> \
  --type browser \
  --url "http://127.0.0.1:<port>/" \
  --focus false
```

Resolve the helper pane exactly as described in the `cmux-workspace` skill. Reuse an existing right helper pane when obvious; when none exists, create one with a right split (`new-pane --direction right` or `split-off`) rather than stacking the artifact behind the active terminal. If `cmux open` fails because the caller env is stale, retry once with `cmux identify --json` output, then report the exact paths if it still fails.

### Step 4: Verify

Before reporting completion:

```bash
test -f "$ASSET_ROOT/index.html"
ls -la "$ASSET_ROOT"
```

For hosted artifacts, also verify the server before handoff:

```bash
curl -fsS "http://127.0.0.1:<port>/healthz"
cmux read-screen --workspace "${CMUX_WORKSPACE_ID:-}" --surface surface:<helper-terminal> --lines 20
```

If opened in cmux, run `cmux list-pane-surfaces --workspace "${CMUX_WORKSPACE_ID:-}" --json` or the closest equivalent to verify the tabs were created.

Also verify there is only one visible surface for the artifact `index.html` in the target helper pane. If the command output still shows duplicates for the same artifact path or title, close stale duplicates before reporting completion.

Verify the artifact landed in its own pane, side by side with the work, not as a background tab in the active terminal's pane. From `list-panes --json`, confirm the workspace has a separate pane holding the artifact browser surface (a non-selected surface sharing the active terminal's pane means it is hidden behind the terminal). If it is buried, `split-off` that surface to the right before reporting completion.

If the artifact was already open before this task, verify that the kept browser surface was reloaded after the final write. Re-run the reload if the final write happened after the last browser command.

## Rules

- Do not leave the final artifact only in `/tmp`.
- Do not claim a run passed unless the linked transcript shows it.
- Do not paste secrets into artifacts. Redact API keys, tokens, cookies, and Authorization headers before copying logs.
- Do not steal focus. Use explicit workspace and pane refs plus `--no-focus` or `--focus false`.
- The caller workspace is the default, not a hard requirement. Standalone durable artifacts may open in a dedicated or new workspace; create it additively and only switch when the user asked to view it now.
- Do not open a top-level repo or generic localhost page when a specific artifact path or deep link exists.
- Keep the final chat answer short and include the durable artifact path plus the concrete next action.
