#!/usr/bin/env python3
"""UltimateRobloxKit installer. Stdlib only, Python 3.9+, macOS, Windows and Linux.

Install into a project (.claude/ in that folder):
  python3 scripts/install/install.py --target ~/games/MyGame
Install for your user account (~/.claude/), available in every project:
  python3 scripts/install/install.py --user
Choose what to install:
  --skills roblox-networking,roblox-ui-systems   only these (plus dependencies, router, conventions)
  --category roblox,modeling                       whole categories
  --no-agents / --no-commands                       skip subagents or slash commands
  --with-mcp                                        merge MCP server examples into <target>/.mcp.json
  --with-claude-md                                  add a short kit section to CLAUDE.md (between markers)
Safety and lifecycle:
  --dry-run          print every action, write nothing
  --update           re-install over a previous install (kit files only; your edits are protected)
  --uninstall        remove exactly what the manifest says was installed
  --force            allow replacing files the kit does not own or you edited; originals are backed
                     up to .claude/.urk-backup/<timestamp>/ first
  --require-version  refuse unless the kit's VERSION equals this (version pinning)
  --list             show skills and categories, then exit

Nothing outside the target's .claude/ folder is touched, except .mcp.json and CLAUDE.md, and only with
their explicit flags. A manifest (.claude/ultimate-roblox-kit.json) records every installed file and
its hash, so updates and uninstalls never remove or overwrite anything the kit did not put there.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.env import KIT_ROOT  # noqa: E402
from lib.skills import discover, with_dependencies  # noqa: E402

MANIFEST = "ultimate-roblox-kit.json"
SUPPORT_DIR = "ultimate-roblox-kit"
SUPPORT_TREES = ["scripts", "tools", "templates", "integrations", "catalog", "examples", "docs/workflows", "VERSION", "LICENSE", "THIRD_PARTY_NOTICES.md"]
ALWAYS = ["roblox-kit-router", "kit-conventions"]
MD_START, MD_END = "<!-- ULTIMATE-ROBLOX-KIT:START -->", "<!-- ULTIMATE-ROBLOX-KIT:END -->"
IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def kit_version() -> str:
    return (KIT_ROOT / "VERSION").read_text().strip()


def kit_commit() -> str:
    try:
        out = subprocess.run(["git", "-C", str(KIT_ROOT), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10)
        return out.stdout.strip() or "unknown"
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


class Plan:
    """Collects (source, destination) copies, then checks conflicts and applies them."""

    def __init__(self, claude: Path, previous: dict, dry: bool, force: bool):
        self.claude, self.previous, self.dry, self.force = claude, previous, dry, force
        self.copies: list[tuple[Path, Path]] = []
        self.backup_root = claude / ".urk-backup" / time.strftime("%Y%m%d-%H%M%S")
        self.log: list[str] = []

    def add_tree(self, src: Path, dest: Path):
        if src.is_file():
            self.copies.append((src, dest))
            return
        for f in sorted(src.rglob("*")):
            if f.is_file() and "__pycache__" not in f.parts and f.name != ".DS_Store":
                self.copies.append((f, dest / f.relative_to(src)))

    def conflicts(self):
        """Destinations that exist and are not unmodified kit files from the previous install."""
        owned = self.previous.get("files", {})
        out = []
        for src, dest in self.copies:
            if not dest.exists():
                continue
            rel = dest.relative_to(self.claude.parent).as_posix()
            if rel in owned and owned[rel] == sha(dest):
                continue  # ours and untouched: safe to replace
            if sha(dest) == sha(src):
                continue  # identical content
            out.append(dest)
        return out

    def apply(self):
        files = {}
        for src, dest in self.copies:
            rel = dest.relative_to(self.claude.parent).as_posix()
            files[rel] = sha(src)
            if dest.exists() and sha(dest) == sha(src):
                continue
            if dest.exists() and dest in self._conflicts:
                backup = self.backup_root / dest.relative_to(self.claude.parent)
                self.log.append(f"backup  {rel} -> {backup.relative_to(self.claude.parent).as_posix()}")
                if not self.dry:
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(dest, backup)
            self.log.append(f"{'update ' if dest.exists() else 'add    '} {rel}")
            if not self.dry:
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dest)
        return files

    def run(self):
        self._conflicts = set(self.conflicts())
        if self._conflicts and self.dry and not self.force:
            for c in sorted(self._conflicts):
                self.log.append(f"CONFLICT {c.relative_to(self.claude.parent).as_posix()} (a real run needs --force; it would be backed up)")
            self._conflicts = set()
        if self._conflicts and not self.force:
            lines = "\n  ".join(p.relative_to(self.claude.parent).as_posix() for p in sorted(self._conflicts))
            raise SystemExit(f"Refusing to overwrite files the kit does not own or that you changed:\n  {lines}\n"
                             "Re-run with --force to replace them (originals are backed up first), or move them away.")
        return self.apply()


def select_skills(all_skills: dict, names, categories):
    if not names and not categories:
        chosen = sorted(all_skills)
    else:
        chosen = list(ALWAYS)
        for n in names or []:
            if n not in all_skills:
                raise SystemExit(f"Unknown skill {n!r}. Use --list.")
            chosen.append(n)
        for c in categories or []:
            in_cat = [s for s, v in all_skills.items() if v["category"] == c]
            if not in_cat:
                raise SystemExit(f"Unknown category {c!r}. Use --list.")
            chosen.extend(in_cat)
    return with_dependencies(dict.fromkeys(chosen), all_skills)


def merge_mcp(target_root: Path, dry: bool, log: list, backup_root: Path):
    example = json.loads((KIT_ROOT / "integrations/mcp/mcp.example.json").read_text())["mcpServers"]
    path = target_root / ".mcp.json"
    current = json.loads(path.read_text()) if path.exists() else {}
    servers = current.setdefault("mcpServers", {})
    added = [k for k in example if k not in servers]
    for k in added:
        servers[k] = example[k]
    if not added:
        log.append("mcp     .mcp.json already has every example server; unchanged")
        return []
    log.append(f"mcp     .mcp.json += {', '.join(added)}")
    if not path.exists():
        added.append("__created__")
    if not dry:
        if path.exists():
            backup_root.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup_root / ".mcp.json")
        path.write_text(json.dumps(current, indent=2) + "\n")
    return added


def claude_md_block(user: bool) -> str:
    urk = "~/.claude/ultimate-roblox-kit" if user else ".claude/ultimate-roblox-kit"
    return f"""{MD_START}
## UltimateRobloxKit

Roblox and Blender skills are installed. For multi-step Roblox, Luau, Blender or game-production work,
start with the `roblox-kit-router` skill, or run `python3 {urk}/scripts/automation/route.py "<task>"`,
and load only the skills it names. Kit scripts live in `{urk}` (written `$URK` in skills).
Never publish, upload or change a live Roblox place without explicit permission.
{MD_END}
"""


def write_claude_md(path: Path, block: str, dry: bool, log: list):
    text = path.read_text() if path.exists() else ""
    if MD_START in text:
        head, rest = text.split(MD_START, 1)
        _, tail = rest.split(MD_END, 1)
        new = head + block.rstrip("\n") + tail
    else:
        new = (text.rstrip("\n") + "\n\n" if text else "") + block
    if new != text:
        log.append(f"edit    {path.name} (kit section between markers)")
        if not dry:
            path.write_text(new)
    return not text


def remove_claude_md(path: Path, dry: bool, log: list):
    if not path.exists():
        return
    text = path.read_text()
    if MD_START not in text:
        return
    head, rest = text.split(MD_START, 1)
    _, tail = rest.split(MD_END, 1)
    remaining = (head.rstrip("\n") + "\n" + tail.lstrip("\n")).strip("\n")
    log.append(f"edit    {path.name} (kit section removed)" if remaining else f"remove  {path.name} (only held the kit section)")
    if not dry:
        if remaining:
            path.write_text(remaining + "\n")
        else:
            path.unlink()


def uninstall(claude: Path, dry: bool, force: bool):
    mpath = claude / MANIFEST
    if not mpath.exists():
        raise SystemExit(f"No kit installation found at {claude} (missing {MANIFEST}).")
    manifest = json.loads(mpath.read_text())
    root = claude.parent
    log, kept = [], []
    for rel, digest in sorted(manifest["files"].items()):
        p = root / rel
        if not p.exists():
            continue
        if sha(p) != digest and not force:
            kept.append(rel)
            continue
        log.append(f"remove  {rel}")
        if not dry:
            p.unlink()
    for rel in sorted({str(Path(r).parent) for r in manifest["files"]}, key=len, reverse=True):
        d = root / rel
        while not dry and d != claude and d.is_dir() and not any(d.iterdir()):
            d.rmdir()
            d = d.parent
    if manifest.get("claude_md"):
        remove_claude_md(root / manifest["claude_md"], dry, log)
    if manifest.get("mcp_servers"):
        mcp = root / ".mcp.json"
        if mcp.exists():
            data = json.loads(mcp.read_text())
            names = [k for k in manifest["mcp_servers"] if k != "__created__"]
            for k in names:
                data.get("mcpServers", {}).pop(k, None)
            log.append(f"mcp     .mcp.json -= {', '.join(names)}")
            created_empty = "__created__" in manifest["mcp_servers"] and data == {"mcpServers": {}}
            if not dry:
                if created_empty:
                    mcp.unlink()
                else:
                    mcp.write_text(json.dumps(data, indent=2) + "\n")
    log.append(f"remove  {mpath.relative_to(root).as_posix()}")
    if not dry:
        mpath.unlink()
    for line in log:
        print(("[dry-run] " if dry else "") + line)
    if kept:
        print("Kept (you edited them; use --force to remove):\n  " + "\n  ".join(kept))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    where = ap.add_mutually_exclusive_group()
    where.add_argument("--target", type=Path, help="project folder (default: current folder)")
    where.add_argument("--user", action="store_true", help="install into ~/.claude for all projects")
    ap.add_argument("--skills", type=lambda s: [x.strip() for x in s.split(",") if x.strip()])
    ap.add_argument("--category", type=lambda s: [x.strip() for x in s.split(",") if x.strip()])
    ap.add_argument("--no-agents", action="store_true")
    ap.add_argument("--no-commands", action="store_true")
    ap.add_argument("--with-mcp", action="store_true")
    ap.add_argument("--with-claude-md", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--require-version")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args(argv)

    all_skills = discover()
    if a.list:
        cats = {}
        for s in all_skills.values():
            cats.setdefault(s["category"], []).append(s["name"])
        for c in sorted(cats):
            print(f"{c}: {', '.join(sorted(cats[c]))}")
        return 0
    if a.require_version and a.require_version != kit_version():
        raise SystemExit(f"Kit version is {kit_version()}, but {a.require_version} was required. Check out tag v{a.require_version}.")

    root = Path.home() if a.user else (a.target or Path.cwd()).expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Target folder does not exist: {root}")
    if not a.user and root == KIT_ROOT.resolve() and not a.dry_run:
        print("Note: installing into the kit's own repository (its .claude/skills is git-ignored).")
    claude = root / ".claude"
    if a.uninstall:
        return uninstall(claude, a.dry_run, a.force)

    mpath = claude / MANIFEST
    previous = json.loads(mpath.read_text()) if mpath.exists() else {}
    if previous and not a.update:
        raise SystemExit(f"The kit is already installed at {claude} (version {previous.get('version')}). Use --update or --uninstall.")

    names = select_skills(all_skills, a.skills, a.category)
    plan = Plan(claude, previous, a.dry_run, a.force)
    for n in names:
        plan.add_tree(KIT_ROOT / all_skills[n]["path"], claude / "skills" / n)
    if not a.no_agents:
        plan.add_tree(KIT_ROOT / ".claude/agents", claude / "agents")
    if not a.no_commands:
        plan.add_tree(KIT_ROOT / ".claude/commands", claude / "commands")
    for item in SUPPORT_TREES:
        plan.add_tree(KIT_ROOT / item, claude / SUPPORT_DIR / item)
    files = plan.run()

    # On update, remove kit files the new selection no longer includes (only if unmodified).
    for rel, digest in previous.get("files", {}).items():
        p = root / rel
        if rel not in files and p.exists() and sha(p) == digest:
            plan.log.append(f"remove  {rel}")
            if not a.dry_run:
                p.unlink()

    mcp_servers = previous.get("mcp_servers", [])
    if a.with_mcp:
        mcp_servers = sorted(set(mcp_servers) | set(merge_mcp(root, a.dry_run, plan.log, plan.backup_root)))
    claude_md = previous.get("claude_md")
    if a.with_claude_md:
        md_path = claude / "CLAUDE.md" if a.user else root / "CLAUDE.md"
        write_claude_md(md_path, claude_md_block(a.user), a.dry_run, plan.log)
        claude_md = md_path.relative_to(root).as_posix()

    manifest = {"kit": "UltimateRobloxKit", "version": kit_version(), "commit": kit_commit(), "installed_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "scope": "user" if a.user else "project", "skills": names, "files": files, "mcp_servers": mcp_servers, "claude_md": claude_md}
    for line in plan.log:
        print(("[dry-run] " if a.dry_run else "") + line)
    if not a.dry_run:
        claude.mkdir(parents=True, exist_ok=True)
        mpath.write_text(json.dumps(manifest, indent=1) + "\n")
    verb = "Would install" if a.dry_run else ("Updated" if previous else "Installed")
    print(f"{verb} UltimateRobloxKit {kit_version()}: {len(names)} skills into {claude}"
          + ("" if a.dry_run else f". Kit scripts: {claude / SUPPORT_DIR}. Start a new Claude Code session to load skills."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
