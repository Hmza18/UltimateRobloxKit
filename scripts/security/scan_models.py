#!/usr/bin/env python3
"""Scan Roblox models and scripts for backdoors and risky code before you use them. Reads only.

  python3 scripts/security/scan_models.py path/to/Model.rbxmx src/ [--json] [--min-severity medium]

Scans .lua/.luau files and XML models and places (.rbxmx, .rbxlx). For binary .rbxm/.rbxl, use the
Lune twin `lune run scripts/security/scan_models.luau <file>` (same rules), or save as .rbxmx in Studio.
Exit code 1 when any HIGH finding exists, so CI can gate free models.

Findings are leads, not verdicts: a legitimate admin system may use HttpService. Read every flagged
line before deciding. Never run a model you have not scanned in a place connected to real data.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

# (id, severity, pattern, why). Kept in sync with scan_models.luau by tests/test_security_scan.py.
RULES = [
    ("require-asset-id", "high", r"\brequire\s*\(\s*\d{5,}\s*\)", "Loads a module from the Roblox library by id: classic backdoor loader"),
    ("require-tonumber", "high", r"\brequire\s*\(\s*tonumber\s*\(", "Loads a module by a computed id"),
    ("loadstring", "high", r"\bloadstring\s*\(", "Runs code from a string (only possible with LoadStringEnabled)"),
    ("getfenv-setfenv", "high", r"\b[gs]etfenv\s*\(", "Rewrites function environments, used to hide behaviour"),
    ("get-objects", "high", r":\s*GetObjects\s*\(|InsertService\s*\)?\s*:\s*LoadAsset(Version)?\s*\(", "Inserts remote assets at runtime"),
    ("string-char-chain", "high", r"(string\.char\s*\(\s*\d+\s*(,\s*\d+\s*){12,}\))", "Long string.char chain: hides a string such as an asset id or URL"),
    ("escaped-bytes", "medium", r"(\\\d{2,3}){12,}|(\\x[0-9a-fA-F]{2}){12,}", "Long escaped byte sequence: obfuscated text"),
    ("http-request", "medium", r"HttpService\s*\)?\s*:\s*(PostAsync|GetAsync|RequestAsync)\s*\(|\bHttpService\b.*\b(PostAsync|RequestAsync)\b", "Sends or fetches data over HTTP"),
    ("webhook", "high", r"discord(app)?\.com/api/webhooks|hooks\.slack\.com|webhook\.site", "Posts to a chat webhook (often used to leak data)"),
    ("teleport-elsewhere", "medium", r"TeleportService\s*\)?\s*:\s*Teleport(Async|ToPlaceInstance)?\s*\(\s*\d{6,}", "Teleports players to a hard-coded place"),
    ("prompt-purchase", "medium", r"MarketplaceService\s*\)?\s*:\s*Prompt(Purchase|ProductPurchase|GamePassPurchase|PremiumPurchase)\s*\(", "Prompts purchases (unexpected in a prop or tool)"),
    ("server-kick-ban", "low", r":\s*Kick\s*\(|BanAsync\s*\(", "Kicks or bans players"),
    ("long-base64", "medium", r"[\"'][A-Za-z0-9+/]{180,}={0,2}[\"']", "Very long base64-like string: packed payload"),
    ("hidden-name", "low", r"\b(Vaccine|Virus|Infected|Backdoor|Fix\s*Lag|Anti\s*Lag|Spread)\b", "Script name or text used by known malicious models"),
]
SEVERITY = {"low": 1, "medium": 2, "high": 3}
COMPILED = [(i, s, re.compile(p, re.IGNORECASE if i == "hidden-name" else 0), w) for i, s, p, w in RULES]


def scripts_in_xml(text: str):
    """Yield (script name, source) from an XML model or place."""
    for m in re.finditer(r'<Item class="(Script|LocalScript|ModuleScript)"[^>]*>(.*?)</Item>', text, re.S):
        body = m.group(2)
        name = re.search(r'<string name="Name">(.*?)</string>', body, re.S)
        src = re.search(r'<ProtectedString name="Source">(?:<!\[CDATA\[(.*?)\]\]>|(.*?))</ProtectedString>', body, re.S)
        if src:
            yield f"{m.group(1)} {html.unescape(name.group(1)) if name else '?'}", src.group(1) if src.group(1) is not None else html.unescape(src.group(2))


def scan_source(label: str, source: str):
    findings = []
    for n, line in enumerate(source.splitlines(), 1):
        for rule_id, sev, pattern, why in COMPILED:
            if pattern.search(line):
                findings.append({"where": f"{label}:{n}", "rule": rule_id, "severity": sev, "why": why, "line": line.strip()[:160]})
    for rule_id, sev, pattern, why in COMPILED:  # name-based rule also checks the script name itself
        if rule_id == "hidden-name" and pattern.search(label):
            findings.append({"where": label, "rule": rule_id, "severity": sev, "why": why, "line": ""})
    return findings


def scan_path(path: Path):
    findings, scanned = [], 0
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for f in files:
        suffix = f.suffix.lower()
        if suffix in (".lua", ".luau"):
            scanned += 1
            findings += scan_source(str(f), f.read_text(encoding="utf-8", errors="replace"))
        elif suffix in (".rbxmx", ".rbxlx"):
            for label, src in scripts_in_xml(f.read_text(encoding="utf-8", errors="replace")):
                scanned += 1
                findings += scan_source(f"{f} > {label}", src)
        elif suffix in (".rbxm", ".rbxl") and path.is_file():
            raise SystemExit(f"{f} is binary: run `lune run scripts/security/scan_models.luau {f}` or save it as .rbxmx")
    return findings, scanned


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--min-severity", choices=list(SEVERITY), default="low")
    a = ap.parse_args(argv)
    findings, scanned = [], 0
    for p in a.paths:
        f, s = scan_path(p)
        findings += f
        scanned += s
    findings = [f for f in findings if SEVERITY[f["severity"]] >= SEVERITY[a.min_severity]]
    findings.sort(key=lambda f: -SEVERITY[f["severity"]])
    if a.json:
        print(json.dumps({"scripts": scanned, "findings": findings}, indent=1))
    else:
        for f in findings:
            print(f"{f['severity'].upper():6} {f['rule']:20} {f['where']}\n       {f['why']}\n       {f['line']}")
        high = sum(f["severity"] == "high" for f in findings)
        print(f"{scanned} scripts scanned, {len(findings)} findings ({high} high)")
    return 1 if any(f["severity"] == "high" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
