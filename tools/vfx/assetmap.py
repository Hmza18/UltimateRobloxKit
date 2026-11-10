#!/usr/bin/env python3
"""Record the Roblox asset ids of uploaded VFX textures and emit the Luau map games use. Stdlib only.

  python3 tools/vfx/assetmap.py template                 # print a CSV to fill in (key,file,assetId)
  python3 tools/vfx/assetmap.py template --format json --out vfx-ids.json
  python3 tools/vfx/assetmap.py apply vfx-ids.csv        # validate, update assets/vfx/manifest.json, print Luau
  python3 tools/vfx/assetmap.py apply vfx-ids.csv --out src/shared/VfxTextures.luau
  python3 tools/vfx/assetmap.py status                   # how many keys have an id
  python3 tools/vfx/assetmap.py luau                     # print the Luau map from the manifest as it is

This tool never talks to Roblox: no upload, no network, no id lookup. Upload the PNGs yourself
(Creator Hub or the Studio Asset Manager, see assets/vfx/README.md), copy each asset id into the
template, then run `apply`. It cannot tell whether an id really is the texture you meant, only that
it has the shape of an asset id.

Map file formats
  CSV   header `key,file,assetId` (file is informational); an empty assetId leaves that key alone
  JSON  { "glow": 1234567890, "spark": "rbxassetid://1234567891", "ring": null }; null clears the id

Ids may be written as 1234567890, "1234567890", "rbxassetid://1234567890" or a create.roblox.com
asset URL. `apply` changes nothing unless every row is valid.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets" / "vfx" / "manifest.json"
GROUPS = ("textures", "flipbooks")
MAX_ID = 2 ** 53 - 1  # ids are stored as Lua numbers by many tools; stay exactly representable
URL = re.compile(r"^https://(?:www\.)?(?:create\.)?roblox\.com/(?:[a-z-]+/)*(?:library|catalog|asset|store/asset|"
                 r"dashboard/creations/store)/(\d+)(?:/.*)?$")
CLEAR = object()


class MapError(Exception):
    """Carries every problem found, so one run reports them all."""

    def __init__(self, problems):
        super().__init__("; ".join(problems))
        self.problems = list(problems)


def parse_id(value):
    """An asset id as int, or raises ValueError saying what is wrong."""
    if isinstance(value, bool):
        raise ValueError("must be a number, not a boolean")
    if isinstance(value, float):
        if not value.is_integer():
            raise ValueError("must be a whole number")
        value = int(value)
    if isinstance(value, int):
        number = value
    elif isinstance(value, str):
        text = value.strip()
        match = re.match(r"^(?:rbxassetid://)?(\d+)$", text) or URL.match(text)
        if not match:
            raise ValueError(f"{value!r} is not an asset id (expected digits, rbxassetid://digits or an asset URL)")
        number = int(match.group(1))
    else:
        raise ValueError(f"{value!r} is not an asset id")
    if number <= 0:
        raise ValueError("must be greater than 0")
    if number > MAX_ID:
        raise ValueError("is too large to be an asset id")
    return number


def load_manifest(path: Path) -> dict:
    if not path.exists():
        raise MapError([f"no manifest at {path}: run python3 tools/vfx/textures.py first"])
    return json.loads(path.read_text(encoding="utf-8"))


def items(manifest: dict) -> list:
    return [item for group in GROUPS for item in manifest.get(group, [])]


def template(manifest: dict, fmt: str = "csv") -> str:
    """A map to fill in, pre-filled with the ids the manifest already has."""
    if fmt == "json":
        return json.dumps({item["key"]: item.get("assetId") for item in items(manifest)}, indent=2) + "\n"
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["key", "file", "assetId"])
    for item in items(manifest):
        writer.writerow([item["key"], item["file"], item.get("assetId") or ""])
    return out.getvalue()


def read_map(path: Path) -> dict:
    """{key: raw value or CLEAR} from a CSV or JSON map. Raises MapError on a malformed file."""
    text = path.read_text(encoding="utf-8-sig")
    if path.suffix.lower() == ".json" or text.lstrip().startswith("{"):
        try:
            data = json.loads(text)
        except json.JSONDecodeError as err:
            raise MapError([f"{path.name}: invalid JSON ({err})"])
        if not isinstance(data, dict):
            raise MapError([f"{path.name}: the JSON map must be an object of key -> asset id"])
        return {str(k): (CLEAR if v is None else v) for k, v in data.items()}
    rows = list(csv.reader(io.StringIO(text)))
    if not rows:
        raise MapError([f"{path.name}: the file is empty"])
    header = [cell.strip() for cell in rows[0]]
    if "key" not in header or "assetId" not in header:
        raise MapError([f"{path.name}: the CSV needs a header with `key` and `assetId` columns"])
    key_col, id_col = header.index("key"), header.index("assetId")
    result, problems = {}, []
    for line, row in enumerate(rows[1:], start=2):
        if not any(cell.strip() for cell in row):
            continue
        key = row[key_col].strip() if key_col < len(row) else ""
        value = row[id_col].strip() if id_col < len(row) else ""
        if not key:
            problems.append(f"{path.name} line {line}: missing key")
        elif key in result:
            problems.append(f"{path.name} line {line}: {key} appears twice")
        elif value:
            result[key] = value
        else:
            result.setdefault(key, None)  # blank id: leave this key as it is
    if problems:
        raise MapError(problems)
    return {k: v for k, v in result.items() if v is not None}


def resolve(manifest: dict, mapping: dict) -> dict:
    """Validated {key: int id or None (clear)}. Raises MapError listing every bad row."""
    known = {item["key"] for item in items(manifest)}
    problems, resolved, seen = [], {}, {}
    for key, value in mapping.items():
        if key not in known:
            problems.append(f"{key}: unknown texture key")
            continue
        if value is CLEAR:
            resolved[key] = None
            continue
        try:
            number = parse_id(value)
        except ValueError as err:
            problems.append(f"{key}: {err}")
            continue
        if number in seen:
            problems.append(f"{key}: asset id {number} is already used by {seen[number]}")
            continue
        seen[number] = key
        resolved[key] = number
    # An id may not collide with one the manifest keeps for a key this map does not touch.
    for item in items(manifest):
        current = item.get("assetId")
        if item["key"] not in resolved and current in seen:
            problems.append(f"{seen[current]}: asset id {current} is already used by {item['key']}")
    if problems:
        raise MapError(problems)
    return resolved


def apply(manifest: dict, resolved: dict) -> dict:
    """A copy of the manifest with the resolved ids written into assetId."""
    updated = json.loads(json.dumps(manifest))
    for item in items(updated):
        if item["key"] in resolved:
            item["assetId"] = resolved[item["key"]]
    return updated


def status(manifest: dict) -> dict:
    all_items = items(manifest)
    mapped = [item["key"] for item in all_items if item.get("assetId")]
    return {"total": len(all_items), "mapped": len(mapped),
            "missing": [item["key"] for item in all_items if not item.get("assetId")]}


def luau(manifest: dict) -> str:
    """Luau module: texture key -> "rbxassetid://id" for every mapped key."""
    lines = ["--!strict",
             "-- Generated by tools/vfx/assetmap.py from assets/vfx/manifest.json. Do not edit: re-run",
             "-- `python3 tools/vfx/assetmap.py apply <map>` after uploading textures.",
             "--",
             "-- Texture key -> asset id for the kit's VFX textures. Keys without an upload are left out,",
             "-- and effects fall back to Roblox's built-in particle textures for them:",
             "--   Visuals.Configure({ textures = require(path.to.VfxTextures) })"]
    flipbooks = [item for item in manifest.get("flipbooks", []) if item.get("assetId")]
    if flipbooks:
        lines += ["--", "-- Flipbook sheets (set ParticleEmitter.FlipbookLayout to match):"]
        lines += [f"--   {item['key']}: Enum.ParticleFlipbookLayout.{item['layout']}, {item['frames']} frames"
                  for item in flipbooks]
    lines.append("")
    mapped = [item for item in items(manifest) if item.get("assetId")]
    if not mapped:
        lines.append("return {} :: { [string]: string }")
    else:
        lines.append("return {")
        lines += [f'\t{item["key"]} = "rbxassetid://{item["assetId"]}",' for item in mapped]
        lines.append("} :: { [string]: string }")
    return "\n".join(lines) + "\n"


def _emit(text: str, out) -> None:
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print(f"wrote {out}", file=sys.stderr)
    else:
        sys.stdout.write(text)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", type=Path, default=MANIFEST, help="manifest to read and update (default assets/vfx)")
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("template", help="write a map of keys to fill with asset ids")
    p.add_argument("--format", choices=("csv", "json"), default="csv")
    p.add_argument("--out", type=Path, help="file to write (default stdout)")
    p = sub.add_parser("apply", help="validate a filled map, update the manifest and emit the Luau map")
    p.add_argument("map", type=Path, help="CSV or JSON map from `template`")
    p.add_argument("--out", type=Path, help="write the Luau module here (default stdout)")
    p.add_argument("--dry-run", action="store_true", help="validate and print, but leave the manifest alone")
    p = sub.add_parser("status", help="how many keys have an asset id")
    p.add_argument("--require-all", action="store_true", help="exit 1 while any key lacks an id")
    p = sub.add_parser("luau", help="emit the Luau map from the manifest as it is")
    p.add_argument("--out", type=Path, help="write the Luau module here (default stdout)")
    a = ap.parse_args(argv)

    try:
        manifest = load_manifest(a.manifest)
        if a.command == "template":
            _emit(template(manifest, a.format), a.out)
        elif a.command == "apply":
            if not a.map.exists():
                raise MapError([f"no such map file: {a.map}"])
            updated = apply(manifest, resolve(manifest, read_map(a.map)))
            if not a.dry_run:
                a.manifest.write_text(json.dumps(updated, indent=2) + "\n", encoding="utf-8")
            state = status(updated)
            note = " (dry run, manifest unchanged)" if a.dry_run else ""
            print(f"{state['mapped']}/{state['total']} keys mapped{note}", file=sys.stderr)
            _emit(luau(updated), a.out)
        elif a.command == "status":
            state = status(manifest)
            print(f"{state['mapped']}/{state['total']} VFX texture keys have an asset id")
            if state["missing"]:
                print("not uploaded: " + ", ".join(state["missing"]))
            if a.require_all and state["missing"]:
                return 1
        elif a.command == "luau":
            _emit(luau(manifest), a.out)
    except MapError as err:
        for problem in err.problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
