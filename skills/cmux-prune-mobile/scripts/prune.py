#!/usr/bin/env python3
"""Prune old dev.cmux.* iOS app installations from booted simulators and paired physical devices.

Usage:
  prune.py --dry-run                # show plan, no uninstalls (default if neither flag passed)
  prune.py --apply                  # actually uninstall
  prune.py --apply --keep 5         # keep latest 5 per surface (default)
  prune.py --apply --simulators-only
  prune.py --apply --physical-only

Behavior notes:
  - Always keeps the untagged `dev.cmux.ios` bundle if present.
  - Snapshots simulator mtimes once up front, before any uninstall, so physical-device ranking
    via the simulator-mtime proxy stays consistent across the run.
  - Tolerates the harmless `Failed to load provisioning paramter list ... Code=1002` noise
    that `devicectl` prefixes onto every call; only the exit code is trusted.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime
from typing import Iterable

CMUX_PREFIX = "dev.cmux."
KEEP_ALWAYS = {"dev.cmux.ios"}


@dataclass
class Surface:
    name: str
    udid: str
    kind: str  # "sim" or "phys"
    bundles: list[tuple[float, str]] = field(default_factory=list)  # (mtime, bid)


def run(args: list[str], capture: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=capture, text=True)


def list_booted_sims() -> list[tuple[str, str]]:
    out = run(["xcrun", "simctl", "list", "devices", "booted"]).stdout
    sims: list[tuple[str, str]] = []
    for line in out.splitlines():
        line = line.strip()
        if "(Booted)" not in line:
            continue
        # Format: "iPhone 17 Pro (D788...UUID...) (Booted)"
        # Take the last paren UUID before "(Booted)".
        try:
            before = line.split(" (Booted)")[0]
            name, _, rest = before.rpartition(" (")
            udid = rest.rstrip(")")
            if name and udid:
                sims.append((name, udid))
        except Exception:
            continue
    return sims


def list_paired_physical() -> list[tuple[str, str]]:
    """Return [(name, udid), ...] for paired/available physical devices."""
    out = run(["xcrun", "devicectl", "list", "devices"]).stdout
    devices: list[tuple[str, str]] = []
    for line in out.splitlines():
        if ".coredevice.local" not in line:
            continue
        parts = line.split()
        # Schema: Name(possibly with spaces)  Hostname  Identifier  State  Model...
        # Find the hostname index by searching for `.coredevice.local`.
        host_idx = next((i for i, p in enumerate(parts) if p.endswith(".coredevice.local")), None)
        if host_idx is None or host_idx + 1 >= len(parts):
            continue
        name = " ".join(parts[:host_idx])
        udid = parts[host_idx + 1]
        if udid:
            devices.append((name, udid))
    return devices


def sim_cmux_bundles(udid: str) -> list[tuple[float, str]]:
    out = run(["xcrun", "simctl", "listapps", udid]).stdout
    bids = []
    for raw in out.splitlines():
        line = raw.strip()
        if line.startswith("CFBundleIdentifier ="):
            v = line.split("=", 1)[1].strip().rstrip(";").strip().strip('"')
            if v.startswith(CMUX_PREFIX):
                bids.append(v)
    apps: list[tuple[float, str]] = []
    for bid in bids:
        r = run(["xcrun", "simctl", "get_app_container", udid, bid, "app"])
        if r.returncode != 0:
            continue
        path = r.stdout.strip()
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        apps.append((mtime, bid))
    return apps


def physical_cmux_bundles(udid: str) -> list[str]:
    json_path = f"/tmp/_cmux_prune_{udid}.json"
    run(["xcrun", "devicectl", "device", "info", "apps", "--device", udid, "--json-output", json_path])
    try:
        d = json.load(open(json_path))
    except Exception:
        return []
    return [
        a["bundleIdentifier"]
        for a in d.get("result", {}).get("apps", [])
        if a.get("bundleIdentifier", "").startswith(CMUX_PREFIX)
    ]


def fmt_ts(ts: float) -> str:
    if not ts:
        return "(unknown)"
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")


def select_keep(
    bundles_with_mtime: Iterable[tuple[float, str]], keep_n: int
) -> tuple[set[str], list[tuple[float, str]]]:
    ranked = sorted(bundles_with_mtime, reverse=True)
    keep: set[str] = set()
    kept_n = 0
    for mtime, bid in ranked:
        if bid in KEEP_ALWAYS:
            keep.add(bid)
        elif kept_n < keep_n:
            keep.add(bid)
            kept_n += 1
    remove = [(m, b) for m, b in ranked if b not in keep]
    return keep, remove


def uninstall_sim(udid: str, bid: str) -> tuple[int, str]:
    r = run(["xcrun", "simctl", "uninstall", udid, bid])
    return r.returncode, (r.stderr or "").strip()


def uninstall_phys(udid: str, bid: str) -> tuple[int, str]:
    r = run(["xcrun", "devicectl", "device", "uninstall", "app", "--device", udid, bid])
    return r.returncode, (r.stderr or "").strip()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--keep", type=int, default=5, help="latest N tagged bundles to keep per surface (default: 5)")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--apply", action="store_true", help="actually uninstall")
    g.add_argument("--dry-run", action="store_true", help="preview only (default)")
    scope = p.add_mutually_exclusive_group()
    scope.add_argument("--simulators-only", action="store_true")
    scope.add_argument("--physical-only", action="store_true")
    args = p.parse_args()

    apply = args.apply
    if not apply and not args.dry_run:
        # Default to dry-run for safety.
        print("(no --apply given; defaulting to --dry-run)\n")

    surfaces: list[Surface] = []

    if not args.physical_only:
        for name, udid in list_booted_sims():
            s = Surface(name=name, udid=udid, kind="sim")
            s.bundles = sim_cmux_bundles(udid)
            surfaces.append(s)

    # Snapshot simulator mtime proxy *before* anything is removed.
    mtime_proxy: dict[str, float] = {}
    for s in surfaces:
        if s.kind == "sim":
            for m, b in s.bundles:
                mtime_proxy[b] = max(mtime_proxy.get(b, 0.0), m)

    if not args.simulators_only:
        for name, udid in list_paired_physical():
            s = Surface(name=name, udid=udid, kind="phys")
            bids = physical_cmux_bundles(udid)
            s.bundles = [(mtime_proxy.get(b, 0.0), b) for b in bids]
            surfaces.append(s)

    plans: list[tuple[Surface, set[str], list[tuple[float, str]]]] = []
    print("=" * 78)
    print(f"cmux-prune-mobile  keep={args.keep}  mode={'APPLY' if apply else 'DRY-RUN'}")
    print("=" * 78)
    for s in surfaces:
        keep, remove = select_keep(s.bundles, args.keep)
        plans.append((s, keep, remove))
        print(f"\n## {s.name} [{s.udid}]  ({s.kind})")
        print(f"   total cmux bundles: {len(s.bundles)}, keep: {len(keep)}, remove: {len(remove)}")
        kept_sorted = sorted(((m, b) for m, b in s.bundles if b in keep), reverse=True)
        for m, b in kept_sorted:
            print(f"     KEEP    {fmt_ts(m)}  {b}")
        if remove:
            head = remove[:5]
            for m, b in head:
                print(f"     REMOVE  {fmt_ts(m)}  {b}")
            if len(remove) > 5:
                print(f"     ... and {len(remove) - 5} more")

    total_remove = sum(len(r) for _, _, r in plans)
    print(f"\nTotal removals planned: {total_remove}")

    if not apply:
        print("\nDry-run only. Re-run with --apply to perform uninstalls.")
        return 0

    if total_remove == 0:
        print("\nNothing to remove.")
        return 0

    # Apply.
    print("\nApplying...")
    summary: dict[str, dict[str, int]] = {}
    failures: list[tuple[str, str, str]] = []

    sim_jobs = [(s.name, s.udid, b) for s, _, rem in plans if s.kind == "sim" for _, b in rem]
    phys_by_dev: dict[tuple[str, str], list[str]] = {}
    for s, _, rem in plans:
        if s.kind == "phys":
            phys_by_dev.setdefault((s.name, s.udid), []).extend(b for _, b in rem)

    # Simulators in parallel (safe).
    if sim_jobs:
        with ThreadPoolExecutor(max_workers=6) as ex:
            futs = {ex.submit(uninstall_sim, udid, bid): (name, bid) for (name, udid, bid) in sim_jobs}
            done = 0
            for f in as_completed(futs):
                name, bid = futs[f]
                rc, err = f.result()
                done += 1
                d = summary.setdefault(name, {"ok": 0, "fail": 0})
                if rc == 0:
                    d["ok"] += 1
                else:
                    d["fail"] += 1
                    failures.append((name, bid, err.splitlines()[-1] if err else ""))
                if done % 25 == 0:
                    print(f"  sim progress: {done}/{len(sim_jobs)}")
        print(f"  sim progress: {len(sim_jobs)}/{len(sim_jobs)} done")

    # Physical: each device sequential (lockdown tunnel serializes), devices in parallel.
    if phys_by_dev:
        def run_phys(item):
            (name, udid), bids = item
            for bid in bids:
                rc, err = uninstall_phys(udid, bid)
                d = summary.setdefault(name, {"ok": 0, "fail": 0})
                if rc == 0:
                    d["ok"] += 1
                else:
                    d["fail"] += 1
                    failures.append((name, bid, err.splitlines()[-1] if err else ""))
            return name

        with ThreadPoolExecutor(max_workers=max(1, len(phys_by_dev))) as ex:
            list(ex.map(run_phys, phys_by_dev.items()))

    print("\n=== RESULTS ===")
    for s, _, _ in plans:
        d = summary.get(s.name, {"ok": 0, "fail": 0})
        print(f"  {s.name}: removed={d['ok']}  failed={d['fail']}")
    if failures:
        print(f"\nFailures ({len(failures)}):")
        for name, bid, err in failures[:20]:
            print(f"  {name}  {bid}: {err}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
