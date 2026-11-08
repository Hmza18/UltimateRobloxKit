#!/usr/bin/env python3
"""Add UltimateRobloxKit Luau library modules to a Rojo project, with their dependencies.

  python3 scripts/automation/add_module.py --list
  python3 scripts/automation/add_module.py UI Systems/Inventory Systems/Shop --project ~/games/MyGame
  python3 scripts/automation/add_module.py --update --project ~/games/MyGame
  python3 scripts/automation/add_module.py --remove Systems/Shop --project ~/games/MyGame

Modules are copied to <project>/<dest> (default src/shared/Urk), keeping the library's folder layout,
so the library's relative string requires keep working. Dependencies are found by following every
`require("./...")` / `require("../...")` in the copied files. A lock file (<dest>/urk-modules.json)
records what was installed and each file's hash:
- --update replaces only files you have not edited; edited files are reported and kept.
- --remove deletes a module's files that you have not edited, unless another module still needs them.
- Existing files the kit did not install are never overwritten.
Use --dry-run to see the plan. Tests and READMEs are copied too (tests into <project>/tests/urk/).
"""
from __future__ import annotations

import argparse
import os
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "library" / "src"
LIB_TESTS = ROOT / "library" / "tests"
REQUIRE = re.compile(r'require\(\s*"(\.{1,2}/[^"]+)"\s*\)')
LOCK = "urk-modules.json"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def modules():
    """Selectable units: top-level folders (Util, UI, Icons) and each Systems/<Name>."""
    out = {}
    for d in sorted(LIB.iterdir()):
        if not d.is_dir():
            continue
        if d.name == "Systems":
            for s in sorted(d.iterdir()):
                if s.is_dir():
                    out[f"Systems/{s.name}"] = s
        else:
            out[d.name] = d
    return out


def resolve(path: Path, spec: str) -> Path:
    target = (path.parent / spec).resolve()
    for cand in (target.with_suffix(".luau"), target / "init.luau", target.with_suffix(".lua")):
        if cand.exists():
            return cand
    raise SystemExit(f"{path.relative_to(ROOT)}: cannot resolve require(\"{spec}\")")


def closure(selected):
    """All library files needed by the selected modules (their own files plus required files)."""
    todo, files = [], set()
    for m in selected:
        for f in sorted(m.rglob("*")):
            if f.is_file() and f.name != ".DS_Store":
                todo.append(f)
    while todo:
        f = todo.pop()
        if f in files:
            continue
        files.add(f)
        if f.suffix == ".luau":
            for spec in REQUIRE.findall(f.read_text(encoding="utf-8")):
                dep = resolve(f, spec)
                if LIB in dep.parents:
                    todo.append(dep)
                    # Requiring any file of a module pulls the module's README too, for documentation.
                    readme = dep.parent / "README.md"
                    if readme.exists():
                        todo.append(readme)
    return sorted(files)


def content(src: Path, dst: Path) -> bytes:
    """Specs require ../src/...; in a project they live in tests/urk/ and the library in <dest>."""
    data = src.read_bytes()
    if src.parent == LIB_TESTS and src.suffix == ".luau":
        rel = Path(os.path.relpath(CONTEXT["dest"], dst.parent)).as_posix()
        data = data.replace(b'require("../src/', f'require("{rel}/'.encode())
    return data


CONTEXT: dict = {}


def tests_for(files):
    """Specs that test the copied files and need nothing else from the library.

    A spec is copied when at least one of its library requires is installed and every one of them
    is, so a spec never fails in a project just because it also covers a module that was not added.
    """
    wanted = set(files)
    out = []
    for spec in sorted(LIB_TESTS.glob("*.spec.luau")):
        libs = [resolve(spec, req) for req in REQUIRE.findall(spec.read_text(encoding="utf-8")) if req.startswith("../src/")]
        if libs and all(path in wanted for path in libs):
            out.append(spec)
    return out


# Generated data modules keep one entry per line on purpose; StyLua must not reflow them.
GENERATED = ("Icons/IconData.luau", "UI/Style/StyleTokens.luau")


def ignore_generated(project: Path, dest: Path, installed) -> None:
    rels = [f"{dest.relative_to(project).as_posix()}/{g}" for g in GENERATED if g in installed]
    if not rels:
        return
    path = project / ".styluaignore"
    lines = path.read_text().splitlines() if path.exists() else []
    missing = [r for r in rels if r not in lines]
    if missing:
        path.write_text("\n".join(lines + missing) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("modules", nargs="*")
    ap.add_argument("--project", type=Path)
    ap.add_argument("--dest", default="src/shared/Urk")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--remove", nargs="+", metavar="MODULE")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    mods = modules()
    if a.list:
        for name, path in mods.items():
            readme = path / "README.md"
            first = ""
            if readme.exists():
                lines = [x for x in readme.read_text(encoding="utf-8").splitlines() if x.strip() and not x.startswith("#")]
                first = lines[0][:90] if lines else ""
            print(f"{name:26} {first}")
        return 0
    if not a.project:
        ap.error("--project is required")
    project = a.project.expanduser().resolve()
    dest = project / a.dest
    CONTEXT["dest"] = dest
    lock_path = dest / LOCK
    lock = json.loads(lock_path.read_text()) if lock_path.exists() else {"modules": [], "files": {}}
    log = []

    if a.remove:
        keep = [m for m in lock["modules"] if m not in a.remove]
        kept_files = closure([mods[m] for m in keep if m in mods])
        needed = {str(f.relative_to(LIB)) for f in kept_files}
        needed |= {f"tests/{t.name}" for t in tests_for(kept_files)}
        if keep:
            needed |= {"tests/lib/t.luau", "tests/run.luau"}
        for rel, digest in sorted(lock["files"].items()):
            if rel in needed:
                continue
            p = project / "tests" / "urk" / rel[len("tests/"):] if rel.startswith("tests/") else dest / rel
            if p.exists() and sha(p) != digest:
                log.append(f"kept    {rel} (edited)")
                continue
            log.append(f"remove  {rel}")
            if not a.dry_run and p.exists():
                p.unlink()
            lock["files"].pop(rel, None)
        lock["modules"] = keep
    else:
        wanted = list(dict.fromkeys(lock["modules"] + a.modules)) if a.update else list(dict.fromkeys(a.modules))
        unknown = [m for m in wanted if m not in mods]
        if unknown:
            raise SystemExit(f"unknown module(s): {', '.join(unknown)}. Use --list.")
        if not wanted:
            ap.error("name at least one module, or use --update")
        files = closure([mods[m] for m in wanted])
        plan = [(f, dest / f.relative_to(LIB), str(f.relative_to(LIB))) for f in files]
        plan += [(t, project / "tests" / "urk" / t.name, f"tests/{t.name}") for t in tests_for(files)]
        plan.append((LIB_TESTS / "lib" / "t.luau", project / "tests" / "urk" / "lib" / "t.luau", "tests/lib/t.luau"))
        plan.append((LIB_TESTS / "run.luau", project / "tests" / "urk" / "run.luau", "tests/run.luau"))
        conflicts = []
        for src, dst, rel in plan:
            if dst.exists() and sha(dst) != hashlib.sha256(content(src, dst)).hexdigest():
                if rel not in lock["files"]:
                    conflicts.append(f"{rel} (not installed by the kit)")
                elif sha(dst) != lock["files"][rel]:
                    log.append(f"kept    {rel} (you edited it; the kit has a newer version)")
                    continue
            if rel in [c.split(" ")[0] for c in conflicts]:
                continue
            same = dst.exists() and sha(dst) == hashlib.sha256(content(src, dst)).hexdigest()
            action = "same   " if same else ("update " if dst.exists() else "add    ")
            if action != "same   ":
                log.append(f"{action} {rel}")
                if not a.dry_run:
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    dst.write_bytes(content(src, dst))
            lock["files"][rel] = hashlib.sha256(content(src, dst)).hexdigest()
        if conflicts:
            raise SystemExit("Refusing to overwrite files the kit did not install:\n  " + "\n  ".join(conflicts))
        lock["modules"] = wanted
    for line in log:
        print(("[dry-run] " if a.dry_run else "") + line)
    if not a.dry_run:
        dest.mkdir(parents=True, exist_ok=True)
        lock_path.write_text(json.dumps(lock, indent=1, sort_keys=True) + "\n")
        ignore_generated(project, dest, lock["files"])
    print(f"{'Would install' if a.dry_run else 'Installed'} {', '.join(lock['modules']) or 'nothing'} in {dest}")
    if not a.dry_run and not a.remove:
        print('Require from ReplicatedStorage, e.g. require(ReplicatedStorage.Shared.Urk.Systems.Inventory.InventoryServer).')
        print("Tests copied to tests/urk/ - run them with `lune run tests/urk/run tests/urk`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
