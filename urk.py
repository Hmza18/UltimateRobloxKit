#!/usr/bin/env python3
"""urk: one entry point for UltimateRobloxKit. Python 3.9+, standard library only.

  python3 urk.py setup --project ~/games/MyGame              # doctor, install, library, checks
  python3 urk.py setup --project ~/games/MyGame --profile assets --with-mcp --dry-run
  python3 urk.py new simulator ClickQuest ~/games/ClickQuest  # scaffold a Rojo game
  python3 urk.py add UI Systems/Inventory --project ~/games/MyGame
  python3 urk.py route "add a shop with a currency"
  python3 urk.py doctor --project ~/games/MyGame
  python3 urk.py check ~/games/MyGame                        # validate an installed project
  python3 urk.py icons search coin
  python3 urk.py ui new PetSimShop --name MyShop --project ~/games/MyGame   # screen from a spec
  python3 urk.py ui preview path/to/MyShop.json --open                    # HTML preview of a spec
  python3 urk.py dashboard [--open]                          # local HTML dashboard
  python3 urk.py upgrade --project ~/games/MyGame            # safe update of skills and modules
  python3 urk.py uninstall --project ~/games/MyGame
  python3 urk.py test                                        # kit's own test suite
  python3 urk.py generate "pet simulator with 3 worlds" --name PetLand --out ~/games/PetLand
  python3 urk.py packages --project ~/games/MyGame           # Fusion, Promise, ProfileStore via Wally
  python3 urk.py economy sim tools/economy/examples/pet-sim.json   # balance check before launch
  python3 urk.py assets search coin | dupes | suggest "gold coin" | <batch.json> --out build/x
  python3 urk.py ui extract ref.png | ui compare ref.png capture.png   # visual UI loop
  python3 urk.py audit --project ~/games/MyGame              # security and licence audit
  python3 urk.py build --project ~/games/MyGame              # lint, test and rojo build
  python3 urk.py skills list | search <words> | eval         # skills and routing accuracy
  python3 urk.py memory add decision "Coins never drop on death" --project ~/games/MyGame
  python3 urk.py release check --project ~/games/MyGame      # release gate; never publishes

Every subcommand wraps a script you can also run directly; `urk.py <cmd> --help` shows its options.
Profiles pick skill categories: full, code, assets, ui, design.
"""
from __future__ import annotations

import json
import subprocess
import sys
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PY = sys.executable
SCRIPTS = {
    "install": "scripts/install/install.py", "doctor": "scripts/install/doctor.py", "route": "scripts/automation/route.py",
    "new": "scripts/automation/new_project.py", "add": "scripts/automation/add_module.py",
    "check": "scripts/validate/check_project.py", "test": "scripts/validate/run_all.py",
    "third-party": "scripts/install/third_party.py", "dashboard": "scripts/dashboard/build_dashboard.py",
    "assets": "scripts/export/asset_batch.py", "package": "scripts/export/package_batch.py",
    "generate": "scripts/automation/generate_game.py", "packages": "scripts/automation/packages.py",
    "audit": "scripts/validate/audit.py", "build": "scripts/validate/build.py", "skills": "scripts/automation/skills.py",
    "memory": "scripts/automation/memory.py", "release": "scripts/validate/release.py",
    "registry": "tools/assets/registry.py", "economy": "tools/economy/economy_sim.py",
}
PROFILES = {
    "full": None,
    "code": "orchestration,roblox,toolchain,ui,gameplay,production",
    "assets": "orchestration,toolchain,blender,modeling,environments",
    "ui": "orchestration,roblox,toolchain,ui",
    "design": "orchestration,gameplay,production,ui",
}
LIBRARY_FOR_PROFILE = {"full": ["UI", "Icons"], "code": ["UI", "Icons"], "ui": ["UI", "Icons"], "assets": [], "design": []}


def run(script, args, check=True):
    cmd = [PY, str(ROOT / SCRIPTS[script]), *args]
    print(f"$ {' '.join(Path(c).name if i < 2 else c for i, c in enumerate(cmd))}", flush=True)
    code = subprocess.run(cmd).returncode
    if check and code != 0:
        sys.exit(code)
    return code


def opt(args, name):
    if name in args:
        i = args.index(name)
        return args[i + 1] if i + 1 < len(args) else None
    return None


def setup(args):
    project = opt(args, "--project")
    if not project:
        sys.exit("usage: urk.py setup --project <dir> [--profile full|code|assets|ui|design] [--with-mcp] [--no-library] [--dry-run]")
    profile = opt(args, "--profile") or "full"
    if profile not in PROFILES:
        sys.exit(f"unknown profile {profile}; choose {', '.join(PROFILES)}")
    dry = "--dry-run" in args
    target = Path(project).expanduser().resolve()
    target.mkdir(parents=True, exist_ok=True) if not dry else None
    print(f"== 1/4 environment ({target})")
    run("doctor", ["--project", str(target)])
    print("== 2/4 skills, agents, commands")
    manifest = target / ".claude" / "ultimate-roblox-kit.json"
    install_args = ["--target", str(target), "--with-claude-md"]
    if manifest.exists():
        install_args.append("--update")
    if PROFILES[profile]:
        install_args += ["--category", PROFILES[profile]]
    if "--with-mcp" in args:
        install_args.append("--with-mcp")
    if dry:
        install_args.append("--dry-run")
    run("install", install_args)
    print("== 3/4 Luau library")
    modules = [] if "--no-library" in args else LIBRARY_FOR_PROFILE[profile]
    if modules and (target / "default.project.json").exists():
        # add_module merges with an existing lock and never replaces files you edited.
        lock_exists = (target / "src/shared/Urk/urk-modules.json").exists()
        run("add", [*modules, "--project", str(target), *(["--update"] if lock_exists else []), *(["--dry-run"] if dry else [])])
    elif modules:
        print("   skipped: no default.project.json here (create a game with `urk.py new` first, or add modules later)")
    else:
        print("   skipped for this profile")
    print("== 4/4 configuration check")
    if not dry:
        run("check", [str(target)], check=False)
    print("\nDone. Open a NEW Claude Code session in the project so skills load, then try /urk-route <task>.")


def icons(args):
    sys.path.insert(0, str(ROOT))
    catalog = json.loads((ROOT / "assets/icons/urk/icons.json").read_text())
    if not args or args[0] in ("-h", "--help"):
        print("urk.py icons list [category] | search <query> | build | import <dir> --pack ... (see tools/icons)")
        return 0
    cmd, rest = args[0], args[1:]
    if cmd == "list":
        for i in catalog["icons"]:
            if not rest or i["category"] == rest[0]:
                print(f"{i['name']:14} {i['category']:10} {' '.join(i['tags'])}")
    elif cmd == "search":
        q = " ".join(rest).lower()
        hits = [i for i in catalog["icons"] if q in i["name"] or any(t.startswith(q) for t in i["tags"])]
        for i in hits:
            print(f"{i['name']:14} {i['category']:10} sheet {i['sheet']} at ({i['x']}, {i['y']})")
        if not hits:
            print("no match")
    elif cmd == "build":
        return subprocess.run([PY, str(ROOT / "tools/icons/build_icons.py"), *rest]).returncode
    elif cmd == "import":
        return subprocess.run([PY, str(ROOT / "tools/icons/import_pack.py"), *rest]).returncode
    else:
        sys.exit(f"unknown icons command {cmd}")
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "setup":
        setup(rest)
    elif cmd == "new":
        if len(rest) < 2 or rest[0].startswith("-"):
            return run("new", rest or ["--help"], check=False)
        out = rest[2] if len(rest) > 2 else rest[1]
        return run("new", ["--template", rest[0], "--name", rest[1], "--out", out])
    elif cmd == "upgrade":
        project = opt(rest, "--project") or sys.exit("usage: urk.py upgrade --project <dir> [--dry-run]")
        extra = ["--dry-run"] if "--dry-run" in rest else []
        run("install", ["--target", project, "--update", *extra])
        if (Path(project).expanduser() / "src/shared/Urk/urk-modules.json").exists():
            run("add", ["--update", "--project", project, *extra])
    elif cmd == "uninstall":
        project = opt(rest, "--project") or sys.exit("usage: urk.py uninstall --project <dir> [--dry-run]")
        return run("install", ["--target", project, "--uninstall", *(["--dry-run"] if "--dry-run" in rest else [])], check=False)
    elif cmd == "icons":
        return icons(rest)
    elif cmd == "ui":
        return subprocess.run([PY, str(ROOT / "tools/ui/ui_cli.py"), *rest]).returncode
    elif cmd == "dashboard":
        code = run("dashboard", [a for a in rest if a != "--open"], check=False)
        if code == 0 and "--open" in rest:
            webbrowser.open((ROOT / "dashboard" / "index.html").as_uri())
        return code
    elif cmd == "assets" and rest and rest[0] in ("scan", "search", "suggest", "dupes"):
        return run("registry", rest, check=False)
    elif cmd == "economy":
        if rest and rest[0] == "sim":
            rest = rest[1:]
        return run("economy", rest or ["--help"], check=False)
    elif cmd == "generate":
        if not rest or rest[0].startswith("-"):
            return run("generate", rest or ["--help"], check=False)
        return run("generate", rest, check=False)
    elif cmd == "version":
        print((ROOT / "VERSION").read_text().strip())
    elif cmd in SCRIPTS:
        return run(cmd, rest, check=False)
    else:
        print(f"unknown command {cmd!r}\n")
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
