"""Discover skills under skills/<category>/<name>/SKILL.md and resolve dependencies."""
from __future__ import annotations

from pathlib import Path

from .env import KIT_ROOT
from .frontmatter import load


def skill_files(root: Path = KIT_ROOT):
    """Kit repository: skills/<category>/<name>/SKILL.md. Installed copy (root is
    .claude/ultimate-roblox-kit): the flat .claude/skills/<name>/SKILL.md beside it."""
    if (root / "skills").is_dir():
        return sorted((root / "skills").glob("*/*/SKILL.md")), root
    return sorted((root.parent / "skills").glob("*/SKILL.md")), root.parent


def discover(root: Path = KIT_ROOT):
    skills = {}
    files, base = skill_files(root)
    for path in files:
        meta, body = load(path)
        md = meta.get("metadata", {}) or {}
        if base != root and not md.get("category"):
            continue  # a non-kit skill installed in the same .claude/skills folder
        skills[meta.get("name", path.parent.name)] = {
            "name": meta.get("name"),
            "folder": path.parent.name,
            "category": md.get("category") or path.parent.parent.name,
            "path": path.parent.relative_to(base).as_posix(),
            "description": meta.get("description", ""),
            "triggers": md.get("triggers", []) or [],
            "depends": md.get("depends", []) or [],
            "meta": meta,
            "body_lines": body.count("\n") + 1,
        }
    return skills


def with_dependencies(names, skills, depth=None):
    """Names plus their dependencies, dependencies listed before dependents where possible.

    depth=None follows dependencies transitively (the installer copies everything a skill may
    point to); depth=1 adds only direct dependencies (the router, to keep context small).
    `depends` means "read alongside", so cycles are allowed and simply stop the walk.
    """
    order, seen = [], set()

    def visit(n, level):
        if n in seen:
            return
        if n not in skills:
            raise KeyError(f"unknown skill {n!r}")
        seen.add(n)
        if depth is None or level < depth:
            for d in skills[n]["depends"]:
                visit(d, level + 1)
        order.append(n)

    for n in names:
        visit(n, 0)
    return order
