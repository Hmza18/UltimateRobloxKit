#!/usr/bin/env python3
"""Fetch reviewed third-party skills at their pinned commits, without running any of their code.

  python3 scripts/install/third_party.py list
  python3 scripts/install/third_party.py fetch el4cteo-blender-skills --cache ~/.cache/urk
  python3 scripts/install/third_party.py install el4cteo-blender-skills --target ~/games/MyGame [--skills blender-core,blender-asset-qa] [--dry-run]

Rules enforced here:
- Only repositories with policy "copy" in third_party/manifest.json can be installed.
- The clone is checked out at the full pinned SHA; a short or moved SHA is refused.
- Git hooks are disabled for the clone and no file from it is executed.
- Each installed skill gets UPSTREAM_LICENSE and UPSTREAM_SOURCE files beside its SKILL.md.
- An existing skill folder of the same name is never overwritten.
--source <path> uses a local clone (for offline use and tests); it must contain the pinned commit.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "third_party" / "manifest.json"


def repos():
    return {r["id"]: r for r in json.loads(MANIFEST.read_text())["repositories"]}


def git(*args, cwd=None):
    out = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", *args], cwd=cwd, capture_output=True, text=True, timeout=600)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {out.stderr.strip()}")
    return out.stdout.strip()


def fetch(repo: dict, cache: Path, source: str | None = None) -> Path:
    if not re.fullmatch(r"[0-9a-f]{40}", repo["commit"]):
        raise SystemExit(f"{repo['id']}: commit {repo['commit']!r} is not a full SHA; review and pin it first.")
    dest = cache / repo["id"]
    if not dest.exists():
        cache.mkdir(parents=True, exist_ok=True)
        git("clone", "--no-checkout", "--quiet", source or repo["url"], str(dest))
    git("checkout", "--quiet", "--detach", repo["commit"], cwd=dest)
    head = git("rev-parse", "HEAD", cwd=dest)
    if head != repo["commit"]:
        raise SystemExit(f"{repo['id']}: checked out {head}, expected {repo['commit']}")
    lic = dest / repo.get("license_file", "LICENSE")
    if not lic.exists():
        raise SystemExit(f"{repo['id']}: license file {lic.name} missing at the pinned commit")
    return dest


def install(repo, clone: Path, target: Path, names, dry: bool):
    skills_root = clone / repo.get("skills_dir", "skills")
    names = names or repo["skills"]
    unknown = [n for n in names if n not in repo["skills"]]
    if unknown:
        raise SystemExit(f"Not in the reviewed list for {repo['id']}: {', '.join(unknown)}")
    out = target / ".claude" / "skills"
    done = []
    for n in names:
        src, dest = skills_root / n, out / n
        if not (src / "SKILL.md").exists():
            raise SystemExit(f"{n}: no SKILL.md at {src}")
        if dest.exists():
            print(f"skip    {n} (a skill with this name already exists; not overwritten)")
            continue
        print(f"{'[dry-run] ' if dry else ''}add     .claude/skills/{n}  from {repo['id']}@{repo['commit'][:7]}")
        if not dry:
            shutil.copytree(src, dest, ignore=shutil.ignore_patterns(".git", "__pycache__"))
            shutil.copy2(clone / repo.get("license_file", "LICENSE"), dest / "UPSTREAM_LICENSE")
            (dest / "UPSTREAM_SOURCE").write_text(f"{repo['url']}\ncommit {repo['commit']}\nlicense {repo['license']}\n")
        done.append(n)
    return done


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    f = sub.add_parser("fetch")
    f.add_argument("id")
    f.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "ultimate-roblox-kit")
    f.add_argument("--source")
    i = sub.add_parser("install")
    i.add_argument("id")
    i.add_argument("--target", type=Path, required=True)
    i.add_argument("--skills", type=lambda s: [x for x in s.split(",") if x])
    i.add_argument("--cache", type=Path, default=Path.home() / ".cache" / "ultimate-roblox-kit")
    i.add_argument("--source")
    i.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    all_repos = repos()
    if a.cmd == "list":
        for r in all_repos.values():
            print(f"{r['id']:30} {r['policy']:5} {r['license']:12} {r['commit'][:7]}  {', '.join(r['skills']) or '-'}")
        return 0
    repo = all_repos.get(a.id) or sys.exit(f"unknown id {a.id!r}; see `list`")
    if a.cmd in ("fetch", "install") and repo["policy"] != "copy":
        raise SystemExit(f"{a.id} is '{repo['policy']}' only (license or review status). See its URL: {repo['url']}")
    clone = fetch(repo, a.cache.expanduser(), a.source)
    if a.cmd == "fetch":
        print(f"{a.id} at {repo['commit'][:7]} in {clone}")
        return 0
    install(repo, clone, a.target.expanduser().resolve(), a.skills, a.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
