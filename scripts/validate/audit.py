#!/usr/bin/env python3
"""Security and licence audit for a Rojo game (or for the kit itself).

  python3 scripts/validate/audit.py --project ~/games/MyGame
  python3 scripts/validate/audit.py --kit                      # the kit's own assets and code
  python3 scripts/validate/audit.py --project . --json audit.json --strict

Code rules (Luau under src/, Packages excluded):
  remote-unvalidated   OnServerEvent/OnServerInvoke handler with no type check in its first lines (HIGH)
  client-trusts-amount a server handler takes a price, amount, cost or reward value from the client (HIGH)
  loadstring           loadstring() (HIGH)
  require-asset-id     require(<number>) loads code from the website at run time (HIGH)
  getfenv-setfenv      getfenv/setfenv (MEDIUM)
  http-no-pcall        HttpService request outside pcall (MEDIUM)
  datastore-no-pcall   DataStore Get/Set/UpdateAsync outside pcall (MEDIUM)
  client-gives-currency a LocalScript/client module changing a currency attribute or leaderstats (MEDIUM)
  secret-in-source     something that looks like an API key, cookie or token (HIGH)
Asset rules (images, meshes, audio, fonts):
  no-licence           a media file with no LICENSE*, PROVENANCE.md or icons.json licence beside it (MEDIUM)
  unredistributable    a pack whose PROVENANCE says redistribution is not allowed, in a folder git tracks (HIGH)

Findings are heuristics: each one names the file and line so a person can judge it. Exit code 1 with
--strict when any HIGH finding remains. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA = {".png", ".jpg", ".jpeg", ".fbx", ".obj", ".glb", ".ogg", ".mp3", ".wav", ".ttf", ".otf"}
SKIP = {".git", "node_modules", "Packages", "ServerPackages", "DevPackages", "__pycache__", "build", ".urk"}
VALIDATION = re.compile(r"Validate\.|typeof\(|type\(|check\w*\(|assert\(|tonumber\(|:IsA\(|isFinite|t\.\w+\(")
SECRET = re.compile(r"(_\|WARNING:-DO-NOT-SHARE-THIS|ROBLOSECURITY|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|"
                    r"api[_-]?key\s*=\s*[\"'][A-Za-z0-9_\-]{16,}[\"'])", re.I)
TRUSTED_ARGS = re.compile(r"OnServer(?:Event|Invoke)[^\n]*function\s*\(\s*\w+\s*(?::\s*\w+)?\s*,([^)]*)\)")
MONEY_WORDS = re.compile(r"\b(price|amount|cost|reward|coins|cash|gems|money|value)\b", re.I)


def luau_files(src: Path):
    for p in sorted(src.rglob("*.lua*")):
        if p.suffix in (".lua", ".luau") and not any(part in SKIP for part in p.parts):
            yield p


def in_pcall(lines: list[str], i: int) -> bool:
    # A call wrapped as `local function call() ... end; retry(call)` has the wrapper just after it.
    window = "\n".join(lines[max(0, i - 3): i + 5]).lower()
    return "pcall" in window or "retr" in window


def audit_code(src: Path, base: Path) -> list[dict]:
    out = []
    for path in luau_files(src):
        rel = str(path.relative_to(base))
        text = path.read_text(errors="ignore")
        lines = text.splitlines()
        client = path.name.endswith(".client.luau") or "/client/" in rel.replace("\\", "/")
        for i, line in enumerate(lines):
            code = line.split("--", 1)[0]
            n = i + 1

            def add(rule, sev, msg):
                out.append({"rule": rule, "severity": sev, "file": rel, "line": n, "message": msg})
            if re.search(r"\bloadstring\s*\(", code):
                add("loadstring", "HIGH", "loadstring runs arbitrary code")
            if re.search(r"\brequire\s*\(\s*\d{5,}\s*\)", code):
                add("require-asset-id", "HIGH", "require(assetId) loads code from the website at run time")
            if re.search(r"\b(getfenv|setfenv)\s*\(", code):
                add("getfenv-setfenv", "MEDIUM", "environment tampering")
            if SECRET.search(line):
                add("secret-in-source", "HIGH", "looks like a credential; move it to Secrets or the server, and rotate it")
            if re.search(r"HttpService:(RequestAsync|GetAsync|PostAsync)", code) and not in_pcall(lines, i):
                add("http-no-pcall", "MEDIUM", "HTTP calls can fail; wrap in pcall")
            if re.search(r":(GetAsync|SetAsync|UpdateAsync|IncrementAsync)\(", code) and "DataStore" in text \
                    and "HttpService" not in code and not in_pcall(lines, i):
                add("datastore-no-pcall", "MEDIUM", "DataStore calls can fail; wrap in pcall with retries")
            if client and re.search(r"SetAttribute\(\s*\"(Coins|Cash|Gems|Money|Currency_\w+)\"", code):
                add("client-gives-currency", "MEDIUM", "currency changed on the client does not replicate and hides a design bug")
            if "OnServerEvent" in code or "OnServerInvoke" in code:
                m = TRUSTED_ARGS.search(code)
                if m and MONEY_WORDS.search(m.group(1)):
                    add("client-trusts-amount", "HIGH", f"handler takes ({m.group(1).strip()}) from the client; "
                        "send an id and look the value up on the server")
                body = "\n".join(lines[i: i + 6])
                params = re.search(r"function\s*\(([^)]*)\)", body)
                extra = [x for x in (params.group(1).split(",")[1:] if params else []) if x.strip()]
                if params and extra and not VALIDATION.search(body):
                    add("remote-unvalidated", "HIGH", "remote handler has no argument check in its first lines")
    return out


def licence_near(path: Path, stop: Path) -> tuple[str | None, str]:
    for folder in [path.parent, *path.parent.parents]:
        for name in ("PROVENANCE.md", "LICENSE.md", "LICENSE.txt", "LICENSE", "LICENSE-kenney.txt", "CREDITS.md"):
            f = folder / name
            if f.exists():
                return str(f), f.read_text(errors="ignore")
        icons = folder / "icons.json"
        if icons.exists():
            try:
                data = json.loads(icons.read_text())
            except json.JSONDecodeError:
                data = {}
            note = data.get("licenseNote") or data.get("license")
            if note:
                return str(icons), str(note)
        if folder == stop:
            break
    return None, ""


def tracked(base: Path) -> set[str] | None:
    try:
        out = subprocess.run(["git", "ls-files"], cwd=base, capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return set(out.splitlines())


def audit_assets(base: Path) -> list[dict]:
    out = []
    files = tracked(base)
    seen_dirs: dict[Path, tuple[str | None, str]] = {}
    for path in sorted(base.rglob("*")):
        if path.suffix.lower() not in MEDIA or not path.is_file() or any(p in SKIP for p in path.parts):
            continue
        rel = str(path.relative_to(base))
        if path.parent not in seen_dirs:
            seen_dirs[path.parent] = licence_near(path, base)
        where, text = seen_dirs[path.parent]
        if where is None:
            out.append({"rule": "no-licence", "severity": "MEDIUM", "file": rel, "line": 0,
                        "message": "no licence or provenance file beside this asset; record where it came from"})
            continue
        lowered = text.lower()
        forbids = ("no redistribution" in lowered or "not redistribut" in lowered or "may not redistribute" in lowered)
        if forbids and (files is None or rel in files):
            out.append({"rule": "unredistributable", "severity": "HIGH", "file": rel, "line": 0,
                        "message": f"{Path(where).name} says the pack may not be redistributed, but git tracks it"})
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path)
    ap.add_argument("--kit", action="store_true", help="audit the kit itself")
    ap.add_argument("--json", type=Path)
    ap.add_argument("--strict", action="store_true", help="exit 1 when a HIGH finding remains")
    a = ap.parse_args(argv)
    if not a.project and not a.kit:
        ap.error("pass --project <dir> or --kit")
    base = ROOT if a.kit else a.project.expanduser().resolve()
    srcs = [base / "library" / "src", base / "templates"] if a.kit else [base / "src"]
    findings = []
    for src in srcs:
        if src.exists():
            findings += audit_code(src, base)
    findings += audit_assets(base)
    order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    findings.sort(key=lambda f: (order[f["severity"]], f["file"], f["line"]))
    counts = {s: sum(1 for f in findings if f["severity"] == s) for s in order}
    grouped: dict[tuple, list] = {}
    for f in findings:
        grouped.setdefault((f["severity"], f["rule"], f["message"]), []).append(f)
    for (sev, rule, msg), items in grouped.items():
        where = ", ".join(f"{f['file']}:{f['line']}" if f["line"] else f["file"] for f in items[:5])
        more = f" (+{len(items) - 5} more)" if len(items) > 5 else ""
        print(f"{sev:6} {rule:22} {msg}\n       {where}{more}")
    print(f"\n{base}: {counts['HIGH']} high, {counts['MEDIUM']} medium, {counts['LOW']} low "
          "(heuristics: review each finding)")
    if a.json:
        a.json.write_text(json.dumps({"base": str(base), "counts": counts, "findings": findings}, indent=1) + "\n")
    return 1 if a.strict and counts["HIGH"] else 0


if __name__ == "__main__":
    sys.exit(main())
