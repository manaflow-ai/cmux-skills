---
name: cmux-prune-mobile
description: Clean up old cmux iOS app installations on booted iOS simulators and connected physical iPhone/iPad devices. Trigger when the user asks to "clean up old cmux mobile apps", "prune cmux iOS apps", or "remove old `dev.cmux.ios.*` bundles" from simulators or devices. Lists `dev.cmux.*` bundles, ranks by install timestamp (with a simulator-mtime proxy for physical devices, since `devicectl` does not expose install dates), and uninstalls everything except the latest N per surface.
---

# cmux-prune-mobile

Cleans up old `dev.cmux.*` app installations on booted iOS simulators and paired physical iPhone/iPad devices. Each tagged dev build (`./scripts/reload.sh --tag <tag>`, `ios/scripts/reload.sh --tag <tag>`, `ios/scripts/reload-with-bridge.sh --tag <tag>`) installs a fresh bundle ID like `dev.cmux.ios.<tag>`, so they pile up fast.

## How to use

Always preview first, then prune.

```bash
# Preview only — no uninstalls. Default keeps latest 5 per surface plus dev.cmux.ios when present.
python3 ~/.claude/skills/cmux-prune-mobile/scripts/prune.py --dry-run

# Apply.
python3 ~/.claude/skills/cmux-prune-mobile/scripts/prune.py --apply

# Apply only to simulators (skip physical iPhone/iPad).
python3 ~/.claude/skills/cmux-prune-mobile/scripts/prune.py --apply --simulators-only

# Keep a different count.
python3 ~/.claude/skills/cmux-prune-mobile/scripts/prune.py --apply --keep 10
```

Codex paths: replace `~/.claude/skills/cmux-prune-mobile/` with `~/.codex/skills/cmux-prune-mobile/`. The `~/.codex/skills/cmux-prune-mobile` directory is symlinked to the Claude copy, so the same script is used by both tools.

## What it does

1. Discovers booted simulators via `xcrun simctl list devices booted`.
2. Discovers connected physical devices via `xcrun devicectl list devices`.
3. For each surface, collects all bundles whose IDs start with `dev.cmux.`.
4. Snapshots install timestamps **once, up front**, before any uninstalls. (This is critical: simulator app mtimes drive the ranking for physical devices too, and once a sim bundle is gone the proxy degrades.)
5. Ranks by mtime (newest first) and keeps:
   - The untagged `dev.cmux.ios` bundle if present (always preserved).
   - The latest `--keep N` tagged bundles (default 5).
6. Uninstalls everything else:
   - Simulators: `xcrun simctl uninstall <udid> <bid>` (parallelizable per simulator).
   - Physical devices: `xcrun devicectl device uninstall app --device <udid> <bid>` (sequential per device, since the lockdown tunnel acquisition serializes; ignore the noisy `Failed to load provisioning paramter list ... Code=1002` line that devicectl prefixes onto every call).
7. Prints a summary: `kept`, `removed`, `failed` per surface.

## Notes for the agent

- Always run `--dry-run` first and show the user the proposed plan before applying. Show counts per surface and list the "keep" set.
- After `--apply`, report counts per surface. Don't claim success based on stderr alone (devicectl's preface is benign).
- The `dev.cmux.app.dev.*` bundles (macOS DEV builds) sometimes end up on the iPad simulator; they're treated as old and pruned by default.
- `*.xctrunner` bundles get reinstalled automatically when XCUITests run, so it's safe to let them age out.
- Tagged builds land in `~/Library/Developer/Xcode/DerivedData/cmux-<tag>/...`.
- If `xcrun devicectl` reports `Failed to load provisioning paramter list ... Code=1002` on stderr, that prefix is unrelated noise. Only check the exit code and the `outcome` field in `--json-output`.

## Limitations

- `devicectl` does not expose true install timestamps for paired iPhones and iPads, so physical-device ranking relies on the simulator mtime as a proxy. This works because tags are typically built and reloaded across simulator + device in the same session, so a recent simulator entry implies the same tag is recent on physical too.
- If a tag exists on a physical device but never made it to any booted simulator, its proxy mtime is `0` and it will rank as "ancient". Pass `--keep` higher or rerun while the relevant simulator still has the bundle if precise ordering matters.
- Only operates on **booted** simulators. Boot the relevant simulators first if they should be pruned in the same pass.
