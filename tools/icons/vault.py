#!/usr/bin/env python3
"""Icon vault: import a PAID / private icon pack without altering a single byte of it.

  python3 tools/icons/vault.py status
  python3 tools/icons/vault.py import ~/Downloads/MyIconPack --name mypack --license-file ~/Downloads/MyIconPack/LICENSE.txt
  python3 tools/icons/vault.py verify mypack --source ~/Downloads/MyIconPack
  python3 tools/icons/vault.py registry mypack --export-map
  python3 tools/icons/vault.py registry mypack --map assets/icons/private/mypack/asset-map.csv
  python3 tools/icons/vault.py preview mypack

Rules this tool keeps
- Originals are copied byte-for-byte into <vault>/<pack>/original/ with their relative paths and
  file names unchanged, checked with SHA-256 and made read-only. Nothing is ever redrawn,
  recoloured, renamed, resized, re-encoded, compressed or stripped.
- The vault (default assets/icons/private/) is git-ignored. `import` refuses to copy into a
  location git would track unless the licence allows redistribution (--redistributable with a
  licence file).
- Anything Roblox needs that is not the original (resized PNGs, sprite sheets) is a derivative
  written to <vault>/<pack>/derived/, never over the originals.
- No upload is attempted. Uploading images needs the owner's authenticated Roblox account and is a
  manual step (Studio Asset Manager or Creator Hub); ids are merged afterwards with `registry --map`.

Standard library only. `derive` uses Pillow for resizing and sheet packing when it is importable
and says so; without Pillow it only makes straight copies and reports what it skipped.
See docs/workflows/icon-pack-import.md.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import html
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VAULT = ROOT / "assets" / "icons" / "private"
SCHEMA = 1
ICON_FORMATS = ("png", "svg", "webp", "jpeg", "gif")
PACK_NAME = re.compile(r"^[a-z][a-z0-9-]{0,39}$")
LICENSE_NAME = re.compile(r"(?i)^(licen[sc]e|eula|terms)([ ._-].*)?$")
PENDING = "Icon pack import: PENDING (no pack has been imported into {vault})"
IMPORT_HINT = "python3 tools/icons/vault.py import <source_dir> --name <pack> --license-file <path-to-licence>"


class VaultError(Exception):
    """A refusal or usage problem. main() prints it and returns 2."""


# Hashing and headers --------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _number(text: str) -> Optional[float]:
    match = re.fullmatch(r"\s*([0-9]*\.?[0-9]+)\s*(px)?\s*", text)
    return float(match.group(1)) if match else None


def _clean(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    return int(value) if float(value).is_integer() else round(value, 3)


def _svg_size(data: bytes) -> Tuple[Optional[float], Optional[float]]:
    text = data[:65536].decode("utf-8", errors="ignore")
    tag = re.search(r"<svg\b[^>]*>", text, flags=re.S | re.I)
    if not tag:
        return None, None
    attrs = dict((k.lower(), v) for k, _, v in re.findall(r"([A-Za-z:]+)\s*=\s*(['\"])(.*?)\2", tag.group(0), flags=re.S))
    width = _number(attrs.get("width", ""))
    height = _number(attrs.get("height", ""))
    if width is None or height is None:
        box = re.split(r"[\s,]+", attrs.get("viewbox", "").strip())
        if len(box) == 4:
            try:
                width, height = float(box[2]), float(box[3])
            except ValueError:
                return None, None
        else:
            return None, None
    return width, height


def _jpeg_size(data: bytes) -> Tuple[Optional[int], Optional[int]]:
    index = 2
    while index + 9 < len(data):
        if data[index] != 0xFF:
            index += 1
            continue
        marker = data[index + 1]
        if marker == 0xFF:
            index += 1
            continue
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            index += 2
            continue
        length = struct.unpack(">H", data[index + 2:index + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width = struct.unpack(">HH", data[index + 5:index + 9])
            return width, height
        index += 2 + length
    return None, None


def _webp_size(data: bytes) -> Tuple[Optional[int], Optional[int]]:
    chunk = data[12:16]
    if chunk == b"VP8X" and len(data) >= 30:
        width = 1 + int.from_bytes(data[24:27], "little")
        height = 1 + int.from_bytes(data[27:30], "little")
        return width, height
    if chunk == b"VP8L" and len(data) >= 25 and data[20] == 0x2F:
        bits = int.from_bytes(data[21:25], "little")
        return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
    if chunk == b"VP8 " and len(data) >= 30 and data[23:26] == b"\x9d\x01\x2a":
        width, height = struct.unpack("<HH", data[26:30])
        return width & 0x3FFF, height & 0x3FFF
    return None, None


def probe(path: Path) -> Tuple[str, Optional[float], Optional[float]]:
    """(format, width, height) from the file header. Never modifies the file; unknown sizes are None."""
    suffix = path.suffix.lower()
    try:
        with open(path, "rb") as handle:
            head = handle.read(65536)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                if len(head) >= 24 and head[12:16] == b"IHDR":
                    width, height = struct.unpack(">II", head[16:24])
                    return "png", width, height
                return "png", None, None
            if head[:3] == b"\xff\xd8\xff":
                width, height = _jpeg_size(head + handle.read())
                return "jpeg", width, height
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                width, height = _webp_size(head)
                return "webp", width, height
            if head[:6] in (b"GIF87a", b"GIF89a") and len(head) >= 10:
                width, height = struct.unpack("<HH", head[6:10])
                return "gif", width, height
            if suffix == ".svg" or (suffix == "" and b"<svg" in head[:1024]):
                width, height = _svg_size(head)
                return "svg", _clean(width), _clean(height)
    except OSError:
        return "unreadable", None, None
    known = {".png": "png", ".jpg": "jpeg", ".jpeg": "jpeg", ".webp": "webp", ".gif": "gif"}
    if suffix in known:
        return known[suffix], None, None  # right extension, header not recognised
    return (suffix[1:] if suffix else "other"), None, None


# Names -----------------------------------------------------------------------------------------


def kebab(text: str) -> str:
    """Same rule as tools/icons/import_pack.py: 'Sword_Icon 02' -> 'sword-icon-02' (accents folded)."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", text)
    text = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    return text or "icon"


def pascal(text: str) -> str:
    return "".join(part.capitalize() for part in kebab(text).split("-"))


def tokens(text: str) -> List[str]:
    if not re.search(r"[A-Za-z0-9]", text):
        return []
    return [t for t in kebab(text).split("-") if t]


# Vault layout ----------------------------------------------------------------------------------


class Pack:
    def __init__(self, vault: Path, name: str):
        if not PACK_NAME.match(name):
            raise VaultError("pack names are 1-40 lowercase letters, digits or '-', starting with a letter: %r" % name)
        self.vault = vault
        self.name = name
        self.dir = vault / name
        self.original = self.dir / "original"
        self.manifest_path = self.dir / "manifest.json"
        self.sums_path = self.dir / "SHA256SUMS"
        self.registry_path = self.dir / "registry.json"
        self.derived = self.dir / "derived"

    def manifest(self) -> Dict[str, Any]:
        if not self.manifest_path.is_file():
            raise VaultError("no pack named %r in %s. %s" % (self.name, show(self.vault), IMPORT_HINT))
        return json.loads(self.manifest_path.read_text(encoding="utf-8"))


def show(path: Path) -> str:
    """A path for messages: relative to the kit when inside it, otherwise just the final name."""
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.name or str(path)


def vault_dir(args: argparse.Namespace) -> Path:
    return Path(args.vault).expanduser().resolve() if getattr(args, "vault", None) else DEFAULT_VAULT


def inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def write_text(path: Path, text: str, vault: Path) -> None:
    """Every generated file goes through here: it must be inside the vault and outside original/."""
    resolved = path.resolve()
    if not inside(resolved, vault):
        raise VaultError("refusing to write outside the vault: %s" % path)
    if "original" in resolved.relative_to(vault.resolve()).parts[1:2]:
        raise VaultError("refusing to write into original/: %s" % path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def dump(data: Any) -> str:
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n"


def scan(base: Path) -> List[str]:
    """Relative POSIX paths of every regular file under base (symlinks are not followed)."""
    found: List[str] = []
    if not base.is_dir():
        return found
    for folder, dirs, files in os.walk(base, followlinks=False):
        dirs[:] = sorted(d for d in dirs if not os.path.islink(os.path.join(folder, d)))
        for name in sorted(files):
            full = Path(folder) / name
            if full.is_symlink() or not full.is_file():
                continue
            found.append(full.relative_to(base).as_posix())
    return sorted(found)


def sums_line(digest: str, rel: str) -> str:
    """One sha256sum-compatible line (binary mode marker, GNU escaping for odd names)."""
    if "\\" in rel or "\n" in rel or "\r" in rel:
        escaped = rel.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")
        return "\\%s *%s\n" % (digest, escaped)
    return "%s *%s\n" % (digest, rel)


def parse_sums(text: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for line in text.split("\n"):
        if not line:
            continue
        escaped = line.startswith("\\")
        body = line[1:] if escaped else line
        digest, _, rel = body.partition(" ")
        rel = rel[1:] if rel[:1] in ("*", " ") else rel
        if escaped:
            rel = re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "\\": "\\"}.get(m.group(1), m.group(1)), rel)
        result[rel] = digest
    return result


# Git safety ------------------------------------------------------------------------------------


def git(args: List[str], cwd: Path) -> Optional[subprocess.CompletedProcess]:
    try:
        return subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None


def git_exposure(dest: Path) -> Optional[str]:
    """Why git would publish files written under dest, or None when it is safe / not a repository."""
    anchor = dest
    while not anchor.is_dir():
        anchor = anchor.parent
    top = git(["rev-parse", "--show-toplevel"], anchor)
    if top is None or top.returncode != 0:
        return None
    probe_path = dest / "original" / "probe.png"
    ignored = git(["check-ignore", "-q", "--no-index", str(probe_path)], anchor)
    if ignored is None or ignored.returncode not in (0, 1):
        return "could not ask git whether %s is ignored" % show(dest)
    if ignored.returncode == 1:
        return "%s is inside a git repository and is not git-ignored" % show(dest)
    tracked = git(["ls-files", "--", str(dest)], anchor)
    if tracked is not None and tracked.stdout.strip():
        return "%s already has files tracked by git" % show(dest)
    return None


# import ----------------------------------------------------------------------------------------


def walk_source(source: Path, vault: Path) -> Tuple[List[str], List[str]]:
    """Regular files to copy and the symlinks that were skipped. Raises on links leaving the source."""
    files: List[str] = []
    skipped: List[str] = []
    escaping: List[str] = []
    vault_real = vault.resolve()
    for folder, dirs, names in os.walk(source, followlinks=False):
        here = Path(folder)
        keep = []
        for name in sorted(dirs):
            full = here / name
            if full.is_symlink():
                (skipped if inside(full, source) else escaping).append(full.relative_to(source).as_posix())
            elif full.resolve() == vault_real or inside(full, vault_real):
                continue  # never walk into the vault itself
            else:
                keep.append(name)
        dirs[:] = keep
        for name in sorted(names):
            full = here / name
            rel = full.relative_to(source).as_posix()
            if full.is_symlink():
                (skipped if inside(full, source) else escaping).append(rel)
            elif full.is_file():
                files.append(rel)
            else:
                skipped.append(rel)
    if escaping:
        raise VaultError("refusing to import: these symlinks point outside the source folder:\n  " + "\n  ".join(escaping))
    return sorted(files), sorted(skipped)


def read_only(path: Path) -> None:
    mode = stat.S_IMODE(os.stat(path).st_mode)
    os.chmod(path, mode & ~0o222)


def find_license(source: Path) -> Optional[Path]:
    for child in sorted(source.iterdir(), key=lambda p: p.name.lower()):
        if child.is_file() and not child.is_symlink() and LICENSE_NAME.match(child.stem):
            return child
    return None


def build_manifest(pack: Pack, previous: Optional[Dict[str, Any]], source_name: str, changed: bool,
                   license_info: Dict[str, Any], skipped: List[str]) -> Dict[str, Any]:
    files = []
    formats: Dict[str, int] = {}
    total = 0
    for rel in scan(pack.original):
        full = pack.original / rel
        kind, width, height = probe(full)
        size = full.stat().st_size
        total += size
        formats[kind] = formats.get(kind, 0) + 1
        files.append({"path": rel, "sha256": sha256_file(full), "bytes": size, "format": kind,
                      "width": width, "height": height})
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    imported = now if changed or not previous else previous.get("importedAt", now)
    return {
        "schema": SCHEMA,
        "pack": pack.name,
        "importedAt": imported,
        "firstImportedAt": (previous or {}).get("firstImportedAt", imported),
        "source": source_name,
        "fileCount": len(files),
        "iconCount": sum(1 for f in files if f["format"] in ICON_FORMATS),
        "totalBytes": total,
        "formats": dict(sorted(formats.items())),
        "license": license_info,
        "skipped": skipped,
        "tool": "tools/icons/vault.py",
        "files": files,
    }


def write_manifest(pack: Pack, manifest: Dict[str, Any]) -> None:
    write_text(pack.manifest_path, dump(manifest), pack.vault)
    write_text(pack.sums_path, "".join(sums_line(f["sha256"], "original/" + f["path"]) for f in manifest["files"]),
               pack.vault)


def cmd_import(args: argparse.Namespace) -> int:
    vault = vault_dir(args)
    pack = Pack(vault, args.name)
    source = Path(args.source_dir).expanduser()
    if not source.is_dir():
        raise VaultError("source folder not found: %s" % args.source_dir)
    source = source.resolve()
    if inside(source, vault):
        raise VaultError("the source folder is inside the vault; import from where you downloaded the pack")

    license_src: Optional[Path] = None
    if args.license_file:
        license_src = Path(args.license_file).expanduser()
        if not license_src.is_file():
            raise VaultError("licence file not found: %s" % args.license_file)
        license_src = license_src.resolve()
    else:
        license_src = find_license(source)
    if args.redistributable and license_src is None:
        raise VaultError("--redistributable needs the licence that says so: pass --license-file <path>")

    exposure = git_exposure(pack.dir)
    if exposure and not args.redistributable:
        raise VaultError(
            "refusing to import: %s, so the paid files could be committed.\n"
            "Add the vault to .gitignore, or pass --redistributable with --license-file only if the licence "
            "explicitly permits redistribution." % exposure)

    files, skipped = walk_source(source, vault)
    if not files:
        raise VaultError("no files found under %s" % source.name)

    # Plan first, so a refused import copies nothing.
    plan: List[Tuple[str, str, str]] = []  # (rel, source sha256, action)
    conflicts: List[str] = []
    for rel in files:
        digest = sha256_file(source / rel)
        target = pack.original / rel
        if target.is_symlink() or (target.exists() and not target.is_file()):
            conflicts.append(rel)
        elif target.is_file():
            if sha256_file(target) == digest:
                plan.append((rel, digest, "same"))
            else:
                conflicts.append(rel)
                plan.append((rel, digest, "replace"))
        else:
            plan.append((rel, digest, "copy"))
    if conflicts and not args.force:
        raise VaultError(
            "refusing to overwrite %d file(s) in the vault that differ from the source (use --force to replace):\n  %s"
            % (len(conflicts), "\n  ".join(conflicts[:20]) + ("\n  ..." if len(conflicts) > 20 else "")))

    previous = json.loads(pack.manifest_path.read_text(encoding="utf-8")) if pack.manifest_path.is_file() else None
    copied = replaced = same = 0
    for rel, digest, action in plan:
        target = pack.original / rel
        if action == "same":
            same += 1
            read_only(target)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if action == "replace":
            if target.is_symlink() or not target.is_file():
                raise VaultError("cannot replace %s: it is not a regular file" % rel)
            os.chmod(target, stat.S_IMODE(os.stat(target).st_mode) | 0o200)
            replaced += 1
        else:
            copied += 1
        shutil.copyfile(source / rel, target)  # bytes only: no re-encoding, no metadata rewriting
        info = os.stat(source / rel)
        os.utime(target, (info.st_atime, info.st_mtime))
        if sha256_file(target) != digest:
            raise VaultError("copy check failed for %s: the vault copy does not match the source" % rel)
        read_only(target)

    license_info: Dict[str, Any] = {"file": None, "sha256": None, "redistributable": False, "notes": args.license_notes or ""}
    if license_src is not None:
        dest = pack.dir / "license" / license_src.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            os.chmod(dest, stat.S_IMODE(os.stat(dest).st_mode) | 0o200)
        shutil.copyfile(license_src, dest)
        license_info["file"] = "license/" + license_src.name
        license_info["sha256"] = sha256_file(dest)
        license_info["redistributable"] = bool(args.redistributable)
        if inside(license_src, source):
            license_info["original"] = "original/" + license_src.relative_to(source).as_posix()
    if not license_info["notes"]:
        if license_info["redistributable"]:
            license_info["notes"] = "Owner states the licence permits redistribution. Re-read it before publishing."
        elif license_info["file"]:
            license_info["notes"] = "Private: keep out of public repositories unless the licence explicitly allows redistribution."
        else:
            license_info["notes"] = "No licence file recorded. Treated as private; add one with --license-file."

    manifest = build_manifest(pack, previous, source.name, copied + replaced > 0, license_info, skipped)
    write_manifest(pack, manifest)

    print("Pack '%s' -> %s" % (pack.name, show(pack.dir)))
    print("  copied %d, replaced %d, already identical %d (byte-for-byte, SHA-256 checked, read-only)" % (copied, replaced, same))
    print("  %d files, %d icons, %d bytes; formats: %s" % (
        manifest["fileCount"], manifest["iconCount"], manifest["totalBytes"],
        ", ".join("%s %d" % kv for kv in manifest["formats"].items())))
    if skipped:
        print("  skipped %d symlink(s) / special file(s): %s" % (len(skipped), ", ".join(skipped[:5])))
    extra = sorted(set(f["path"] for f in manifest["files"]) - set(files))
    if extra:
        print("  note: %d file(s) in the vault are not in this source (kept, never deleted)" % len(extra))
    print("  licence: %s; redistributable: %s" % (license_info["file"] or "none recorded", "yes" if license_info["redistributable"] else "no (private)"))
    if exposure:
        print("  WARNING: %s. Imported because --redistributable was given." % exposure)
    print("Next: python3 tools/icons/vault.py verify %s --source <source_dir>; then registry %s --export-map" % (pack.name, pack.name))
    return 0


# verify ----------------------------------------------------------------------------------------


def compare(pack: Pack, manifest: Dict[str, Any]) -> Dict[str, List[str]]:
    recorded = {f["path"]: f["sha256"] for f in manifest["files"]}
    present = scan(pack.original)
    missing = sorted(set(recorded) - set(present))
    extra = sorted(set(present) - set(recorded))
    modified = sorted(rel for rel in present if rel in recorded and sha256_file(pack.original / rel) != recorded[rel])
    return {"missing": missing, "extra": extra, "modified": modified}


def cmd_verify(args: argparse.Namespace) -> int:
    pack = Pack(vault_dir(args), args.pack)
    manifest = pack.manifest()
    report = compare(pack, manifest)
    recorded = {f["path"]: f["sha256"] for f in manifest["files"]}
    sums_ok = True
    if pack.sums_path.is_file():
        sums = parse_sums(pack.sums_path.read_text(encoding="utf-8"))
        sums_ok = sums == {"original/" + k: v for k, v in recorded.items()}
    else:
        sums_ok = False
    source_report: Dict[str, List[str]] = {}
    if args.source:
        source = Path(args.source).expanduser()
        if not source.is_dir():
            raise VaultError("source folder not found: %s" % args.source)
        source = source.resolve()
        files, _ = walk_source(source, pack.vault)
        source_report = {
            "source-only": sorted(set(files) - set(recorded)),
            "vault-only": sorted(set(recorded) - set(files)),
            "differs-from-source": sorted(r for r in files if r in recorded and sha256_file(source / r) != recorded[r]),
        }
    problems = sum(len(v) for v in report.values()) + sum(len(v) for v in source_report.values()) + (0 if sums_ok else 1)
    if args.json:
        print(dump({"pack": pack.name, "ok": problems == 0, "files": len(recorded), "sumsFile": sums_ok,
                    **report, **source_report}), end="")
        return 0 if problems == 0 else 1
    for label, items in list(report.items()) + list(source_report.items()):
        for rel in items:
            print("%s: %s" % (label.upper(), rel))
    if not sums_ok:
        print("SHA256SUMS: missing or does not match manifest.json")
    if problems:
        print("FAILED: pack '%s' differs in %d place(s). The originals must not be edited; re-import from the source." % (pack.name, problems))
        return 1
    against = " and the source folder" if args.source else ""
    print("OK: %d files in pack '%s' match the manifest%s (SHA-256)." % (len(recorded), pack.name, against))
    return 0


# registry --------------------------------------------------------------------------------------


def category_of(rel: str, level: str) -> Tuple[str, Optional[str]]:
    parts = rel.split("/")[:-1]
    if not parts:
        return "uncategorized", None
    if level == "last":
        return kebab(parts[-1]), ("/".join(kebab(p) for p in parts[:-1]) or None)
    if level == "path":
        return "/".join(kebab(p) for p in parts), None
    return kebab(parts[0]), ("/".join(kebab(p) for p in parts[1:]) or None)


def assign_names(items: List[Dict[str, Any]], kept: Dict[str, str]) -> None:
    """Stable kebab names. Paths named by an earlier registry keep their name; clashes get the
    category, then the folder path, then the format as a prefix/suffix, then a number."""
    used = set()
    todo = []
    for item in items:
        name = kept.get(item["original"])
        if name and name not in used:
            item["name"] = name
            used.add(name)
        else:
            todo.append(item)

    def candidates(item: Dict[str, Any]) -> List[str]:
        base = kebab(Path(item["original"]).stem)
        folder = "-".join(kebab(p) for p in item["original"].split("/")[:-1])
        category = item["category"].replace("/", "-")
        options = [base, "%s-%s" % (category, base)]
        options.append("%s-%s" % (folder, base) if folder and folder != category else options[-1])
        options.append("%s-%s" % (options[-1], item["format"]))
        return options

    for depth in range(4):
        groups: Dict[str, List[Dict[str, Any]]] = {}
        for item in todo:
            options = candidates(item)
            groups.setdefault(options[min(depth, len(options) - 1)], []).append(item)
        remaining = []
        for name, members in groups.items():
            if len(members) == 1 and name not in used:
                members[0]["name"] = name
                used.add(name)
            else:
                remaining.extend(members)
        todo = sorted(remaining, key=lambda i: i["original"])
        if not todo:
            return
    for item in todo:
        base = candidates(item)[-1]
        index = 2
        while "%s-%d" % (base, index) in used:
            index += 1
        item["name"] = "%s-%d" % (base, index)
        used.add(item["name"])


ASSET_ID = re.compile(r"(?:^|rbxassetid://|[?&]id=|/(?:library|catalog|asset|assets|store/asset|decals)/)(\d{1,20})(?:$|[/?&#])")


def parse_asset_id(value: Any) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError("not an asset id: %r" % value)
    if isinstance(value, int):
        if value <= 0:
            raise ValueError("not an asset id: %r" % value)
        return value
    text = str(value).strip()
    if text == "":
        return None
    match = ASSET_ID.search(text)
    if not match:
        raise ValueError("not an asset id: %r" % value)
    return int(match.group(1))


def read_map(path: Path) -> List[Tuple[str, Any]]:
    """(key, raw id) pairs from a CSV (columns name/original + assetId) or JSON map file."""
    if not path.is_file():
        raise VaultError("map file not found: %s" % path)
    pairs: List[Tuple[str, Any]] = []
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        if isinstance(data, dict):
            data = data.get("icons", data) if isinstance(data.get("icons"), (list, dict)) else data
        if isinstance(data, dict):
            return [(str(k), v) for k, v in data.items()]
        for row in data:
            value = row.get("assetId", row.get("id"))
            for key in ("original", "name"):
                if row.get(key):
                    pairs.append((str(row[key]), value))
                    break
        return pairs
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        fields = {(f or "").strip().lower().replace("_", "").replace(" ", ""): f for f in (reader.fieldnames or [])}
        id_field = fields.get("assetid") or fields.get("id")
        if id_field is None or not (fields.get("name") or fields.get("original")):
            raise VaultError("%s needs an assetId column and a name or original column" % path.name)
        for row in reader:
            value = row.get(id_field)
            key = (row.get(fields["original"]) if fields.get("original") else None) or \
                  (row.get(fields["name"]) if fields.get("name") else None)
            if key:
                pairs.append((key.strip(), value))
    return pairs


def read_synonyms(path: Path) -> Dict[str, List[str]]:
    if not path.is_file():
        raise VaultError("synonyms file not found: %s" % path)
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise VaultError("synonyms file must be a JSON object: { \"coin\": [\"money\", \"gold\"] }")
    return {kebab(str(k)): [kebab(str(v)) for v in (vs if isinstance(vs, list) else [vs])] for k, vs in data.items()}


def load_sheets(pack: Pack) -> Optional[Dict[str, Any]]:
    path = pack.derived / "sheets" / "sheets.json"
    if not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def build_registry(pack: Pack, manifest: Dict[str, Any], level: str = "first",
                   synonyms: Optional[Dict[str, List[str]]] = None, rename: bool = False) -> Dict[str, Any]:
    previous: Dict[str, Any] = {}
    if pack.registry_path.is_file():
        previous = json.loads(pack.registry_path.read_text(encoding="utf-8"))
    old = {i["original"]: i for i in previous.get("icons", [])}
    items = []
    for entry in manifest["files"]:
        if entry["format"] not in ICON_FORMATS:
            continue
        category, sub = category_of(entry["path"], level)
        items.append({
            "name": "", "category": category, "subcategory": sub, "tags": [],
            "original": entry["path"], "sha256": entry["sha256"], "bytes": entry["bytes"],
            "format": entry["format"], "width": entry["width"], "height": entry["height"],
            "assetId": (old.get(entry["path"]) or {}).get("assetId"),
        })
    assign_names(items, {} if rename else {k: v["name"] for k, v in old.items()})
    words = synonyms or {}
    for item in items:
        tags: List[str] = []
        for token in tokens(item["name"]) + tokens(item["category"]) + tokens(item["subcategory"] or ""):
            if token not in tags and token != "uncategorized":
                tags.append(token)
        for key in [item["name"]] + list(tags):
            for word in words.get(key, []):
                if word not in tags:
                    tags.append(word)
        item["tags"] = tags
    items.sort(key=lambda i: (i["category"], i["name"]))
    registry: Dict[str, Any] = {
        "schema": SCHEMA,
        "pack": pack.name,
        "generatedFrom": "manifest.json",
        "categoryLevel": level,
        "count": len(items),
        "mapped": sum(1 for i in items if i["assetId"]),
        "categories": sorted({i["category"] for i in items}),
        "sheets": previous.get("sheets", []),
        "icons": items,
    }
    sheets = load_sheets(pack)
    if sheets:
        known = {s["file"]: s.get("assetId") for s in registry["sheets"]}
        registry["sheets"] = [{"file": s["file"], "width": s["width"], "height": s["height"],
                               "assetId": known.get(s["file"])} for s in sheets["sheets"]]
        rects = sheets["rects"]
        for item in items:
            rect = rects.get(item["original"])
            if rect:
                item["sheet"] = {"index": rect["sheet"], "x": rect["x"], "y": rect["y"], "w": rect["w"], "h": rect["h"]}
    else:
        registry["sheets"] = []
    return registry


def merge_map(registry: Dict[str, Any], pairs: List[Tuple[str, Any]]) -> Tuple[int, List[str], List[str]]:
    by_name = {i["name"]: i for i in registry["icons"]}
    by_path = {i["original"]: i for i in registry["icons"]}
    sheets = {"@sheet-%d" % (n + 1): s for n, s in enumerate(registry["sheets"])}
    sheets.update({s["file"]: s for s in registry["sheets"]})
    applied = 0
    unknown: List[str] = []
    bad: List[str] = []
    for key, raw in pairs:
        target = by_path.get(key) or by_name.get(key) or sheets.get(key) or by_name.get(key.split(":", 1)[-1])
        if target is None:
            unknown.append(key)
            continue
        try:
            value = parse_asset_id(raw)
        except ValueError:
            bad.append("%s = %r" % (key, raw))
            continue
        if value is not None:
            target["assetId"] = value
            applied += 1
    registry["mapped"] = sum(1 for i in registry["icons"] if i["assetId"])
    return applied, unknown, bad


def luau_module(registry: Dict[str, Any]) -> str:
    """Names, categories, tags, sizes and asset ids only: no image bytes and no original paths.
    Every entry has the same fields (0 means "none"), which keeps the module --!strict clean."""
    def num(value: Any) -> str:
        if value is None:
            return "0"
        return str(int(value)) if float(value).is_integer() else repr(round(float(value), 3))

    has_sheets = bool(registry["sheets"])
    lines = [
        "--!strict",
        "-- Generated by tools/icons/vault.py (registry) for the private icon pack '%s'. Do not edit." % registry["pack"],
        "-- Data only: names, categories, tags, sizes and Roblox asset ids. assetId = 0 means not uploaded yet.",
        "-- Usage: Visuals.Icons.register(\"%s\", require(this))" % registry["pack"],
        "",
        "return {",
        '\tpack = "%s",' % registry["pack"],
        "\tschema = %d," % SCHEMA,
        "\tcount = %d," % len(registry["icons"]),
        "\tsheets = {",
    ]
    for sheet in registry["sheets"]:
        lines.append("\t\t{ width = %s, height = %s, assetId = %s }," % (num(sheet["width"]), num(sheet["height"]), num(sheet.get("assetId"))))
    lines += ["\t},", "\ticons = {"]
    for icon in registry["icons"]:
        tags = ", ".join('"%s"' % t for t in icon["tags"])
        row = '\t\t{ name = "%s", category = "%s", tags = { %s }, width = %s, height = %s, assetId = %s' % (
            icon["name"], icon["category"], tags, num(icon["width"]), num(icon["height"]), num(icon["assetId"]))
        if has_sheets:
            rect = icon.get("sheet") or {"index": 0, "x": 0, "y": 0, "w": 0, "h": 0}
            row += ", sheet = %d, x = %d, y = %d, w = %d, h = %d" % (rect["index"], rect["x"], rect["y"], rect["w"], rect["h"])
        lines.append(row + " },")
    lines += ["\t},", "}", ""]
    return "\n".join(lines)


def write_map_template(path: Path, registry: Dict[str, Any], vault: Path) -> None:
    import io
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["name", "category", "original", "width", "height", "assetId"])
    for n, sheet in enumerate(registry["sheets"]):
        writer.writerow(["@sheet-%d" % (n + 1), "(sprite sheet)", sheet["file"], sheet["width"], sheet["height"], sheet.get("assetId") or ""])
    for icon in registry["icons"]:
        writer.writerow([icon["name"], icon["category"], icon["original"],
                         "" if icon["width"] is None else icon["width"],
                         "" if icon["height"] is None else icon["height"], icon["assetId"] or ""])
    write_text(path, buffer.getvalue(), vault)


def cmd_registry(args: argparse.Namespace) -> int:
    vault = vault_dir(args)
    pack = Pack(vault, args.pack)
    manifest = pack.manifest()
    synonyms = read_synonyms(Path(args.synonyms).expanduser()) if args.synonyms else None
    registry = build_registry(pack, manifest, args.category_level, synonyms, args.rename)
    applied, unknown, bad = 0, [], []
    if args.map:
        applied, unknown, bad = merge_map(registry, read_map(Path(args.map).expanduser()))
    if bad:
        raise VaultError("these map rows are not Roblox asset ids (nothing was written):\n  " + "\n  ".join(bad[:20]))
    map_out: Optional[Path] = None
    if args.export_map is not None:
        map_out = Path(args.export_map).expanduser() if args.export_map else pack.dir / "asset-map.csv"
        if not inside(map_out, vault):
            raise VaultError("the asset-id template lists the pack's file names, so it must stay inside the vault: %s" % show(vault))
        if map_out.is_file() and not args.force and not args.map:
            # Ids already typed into the template are kept, not wiped by a second export.
            merge_map(registry, [(k, v) for k, v in read_map(map_out) if parse_asset_id_safe(v)])
    write_text(pack.registry_path, dump(registry), vault)
    luau_path = Path(args.luau).expanduser() if args.luau else pack.dir / ("%sIcons.luau" % pascal(pack.name))
    if inside(luau_path, vault):
        write_text(luau_path, luau_module(registry), vault)
    else:
        # An explicit --luau outside the vault is the owner's choice: the module has no image data.
        luau_path.parent.mkdir(parents=True, exist_ok=True)
        with open(luau_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(luau_module(registry))
    print("Registry for '%s': %d icons in %d categories, %d with an asset id, %d without" % (
        pack.name, registry["count"], len(registry["categories"]), registry["mapped"], registry["count"] - registry["mapped"]))
    print("  %s" % show(pack.registry_path))
    print("  %s (data only, no image bytes)" % (show(luau_path) if inside(luau_path, ROOT) or inside(luau_path, vault) else str(luau_path)))
    if not inside(luau_path, vault):
        print("  NOTE: that module is outside the private vault. It lists icon names and asset ids; check the licence before committing it.")
    if args.map:
        print("  asset-id map: %d applied, %d unknown key(s)" % (applied, len(unknown)))
        for key in unknown[:10]:
            print("    unknown: %s" % key)
    if map_out is not None:
        out = map_out
        write_map_template(out, registry, vault)
        print("  %s (fill the assetId column after uploading, then: registry %s --map %s)" % (show(out), pack.name, show(out)))
        print("  Uploading is manual: it needs the owner's signed-in Roblox account (Studio Asset Manager or Creator Hub). Nothing was uploaded.")
    return 0


def parse_asset_id_safe(value: Any) -> Optional[int]:
    try:
        return parse_asset_id(value)
    except ValueError:
        return None


# Queries ---------------------------------------------------------------------------------------


def registry_for(pack: Pack) -> Dict[str, Any]:
    if pack.registry_path.is_file():
        return json.loads(pack.registry_path.read_text(encoding="utf-8"))
    return build_registry(pack, pack.manifest())


def rank(icon: Dict[str, Any], query: str) -> int:
    name = icon["name"]
    if name == query:
        return 100
    if name.startswith(query):
        return 60
    if query in name.split("-"):
        return 50
    if query in name:
        return 40
    best = 0
    for tag in icon["tags"]:
        if tag == query:
            best = max(best, 30)
        elif tag.startswith(query):
            best = max(best, 20)
    if best == 0 and query in icon["category"]:
        best = 10
    return best


def search_registry(registry: Dict[str, Any], query: str, limit: Optional[int] = None) -> List[Dict[str, Any]]:
    text = query.split(":", 1)[-1]
    if not re.search(r"[A-Za-z0-9]", text):
        return []
    wanted = kebab(text)
    scored = [(rank(icon, wanted), icon) for icon in registry["icons"]]
    hits = sorted(((s, i) for s, i in scored if s > 0), key=lambda pair: (-pair[0], pair[1]["name"]))
    return [i for _, i in hits][: limit if limit and limit > 0 else None]


def describe(icon: Dict[str, Any]) -> str:
    size = "%sx%s" % (icon["width"], icon["height"]) if icon["width"] is not None else "?"
    asset = "rbxassetid://%d" % icon["assetId"] if icon["assetId"] else "no asset id"
    return "%-36s %-18s %-5s %-10s %s" % (icon["name"], icon["category"], icon["format"], size, asset)


def emit(args: argparse.Namespace, icons: List[Dict[str, Any]]) -> None:
    if args.json:
        print(dump(icons), end="")
        return
    for icon in icons:
        print(describe(icon))
    print("%d icon(s)" % len(icons))


def cmd_search(args: argparse.Namespace) -> int:
    registry = registry_for(Pack(vault_dir(args), args.pack))
    hits = search_registry(registry, args.query, args.limit)
    emit(args, hits)
    return 0 if hits else 1


def cmd_list(args: argparse.Namespace) -> int:
    registry = registry_for(Pack(vault_dir(args), args.pack))
    icons = registry["icons"]
    if args.category:
        wanted = "/".join(kebab(p) for p in args.category.split("/"))
        icons = [i for i in icons if i["category"] == wanted]
    if args.unmapped:
        icons = [i for i in icons if not i["assetId"]]
    emit(args, icons)
    return 0


def cmd_autocomplete(args: argparse.Namespace) -> int:
    registry = registry_for(Pack(vault_dir(args), args.pack))
    prefix = args.prefix.split(":", 1)[-1]
    wanted = kebab(prefix) if re.search(r"[A-Za-z0-9]", prefix) else ""
    names = sorted(i["name"] for i in registry["icons"] if i["name"].startswith(wanted))
    names = names[: args.limit if args.limit and args.limit > 0 else None]
    if args.json:
        print(json.dumps(names))
    else:
        for name in names:
            print(name)
    return 0


def pack_stats(pack: Pack) -> Dict[str, Any]:
    manifest = pack.manifest()
    registry = registry_for(pack)
    categories: Dict[str, int] = {}
    sizes: Dict[str, int] = {}
    for icon in registry["icons"]:
        categories[icon["category"]] = categories.get(icon["category"], 0) + 1
        key = "%sx%s" % (icon["width"], icon["height"]) if icon["width"] is not None else "unknown"
        sizes[key] = sizes.get(key, 0) + 1
    return {
        "pack": pack.name,
        "files": manifest["fileCount"],
        "icons": registry["count"],
        "bytes": manifest["totalBytes"],
        "formats": manifest["formats"],
        "categories": dict(sorted(categories.items())),
        "sizes": dict(sorted(sizes.items(), key=lambda kv: -kv[1])),
        "mapped": registry["mapped"],
        "unmapped": registry["count"] - registry["mapped"],
        "registryWritten": pack.registry_path.is_file(),
        "redistributable": bool(manifest["license"].get("redistributable")),
        "licenseFile": manifest["license"].get("file"),
        "importedAt": manifest["importedAt"],
    }


def cmd_stats(args: argparse.Namespace) -> int:
    stats = pack_stats(Pack(vault_dir(args), args.pack))
    if args.json:
        print(dump(stats), end="")
        return 0
    print("Pack '%s': %d icons (%d files, %d bytes), imported %s" % (stats["pack"], stats["icons"], stats["files"], stats["bytes"], stats["importedAt"]))
    print("  formats: %s" % ", ".join("%s %d" % kv for kv in stats["formats"].items()))
    print("  sizes: %s" % ", ".join("%s %d" % kv for kv in list(stats["sizes"].items())[:8]))
    print("  asset ids: %d mapped, %d missing" % (stats["mapped"], stats["unmapped"]))
    print("  licence: %s; redistributable: %s" % (stats["licenseFile"] or "none recorded", "yes" if stats["redistributable"] else "no (private)"))
    print("  categories:")
    for name, count in stats["categories"].items():
        print("    %-28s %d" % (name, count))
    return 0


def find_packs(vault: Path) -> List[Pack]:
    packs = []
    if vault.is_dir():
        for child in sorted(vault.iterdir()):
            if child.is_dir() and PACK_NAME.match(child.name) and (child / "manifest.json").is_file():
                packs.append(Pack(vault, child.name))
    return packs


def cmd_status(args: argparse.Namespace) -> int:
    vault = vault_dir(args)
    packs = find_packs(vault)
    rows = []
    for pack in packs:
        stats = pack_stats(pack)
        report = compare(pack, pack.manifest())
        differences = sum(len(v) for v in report.values())
        stats["verified"] = differences == 0
        stats["differences"] = differences
        rows.append(stats)
    if args.json:
        print(dump({"vault": show(vault), "pending": not rows, "packs": rows}), end="")
        return 0
    if not rows:
        print(PENDING.format(vault=show(vault)))
        print("The pack files have not been supplied yet. When you have them, run:")
        print("  " + IMPORT_HINT)
        return 0
    print("Icon vault: %s" % show(vault))
    for row in rows:
        state = "verified (SHA-256 matches)" if row["verified"] else "FAILED VERIFICATION (%d difference(s); run verify)" % row["differences"]
        print("  %s: %d icons, %d files, %s" % (row["pack"], row["icons"], row["files"], state))
        print("    asset ids: %d of %d mapped%s" % (row["mapped"], row["icons"], "" if row["registryWritten"] else " (registry not built yet: run registry)"))
        print("    licence: %s; redistributable: %s" % (row["licenseFile"] or "none recorded", "yes" if row["redistributable"] else "no (private)"))
    return 0


# derive ----------------------------------------------------------------------------------------


def pillow():
    """Pillow's Image module when importable, else None. URK_VAULT_NO_PILLOW=1 forces the stdlib path."""
    if os.environ.get("URK_VAULT_NO_PILLOW") == "1":
        return None
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        return None
    return Image


def cmd_derive(args: argparse.Namespace) -> int:
    vault = vault_dir(args)
    pack = Pack(vault, args.pack)
    registry = registry_for(pack)
    size = args.size
    if size < 8 or size > 1024:
        raise VaultError("--size must be between 8 and 1024 (Roblox images are at most 1024 px)")
    image_module = pillow()
    out_dir = pack.derived / str(size)
    entries: List[Dict[str, Any]] = []
    counts = {"copy": 0, "resize": 0, "skipped": 0}
    for icon in registry["icons"]:
        source = pack.original / icon["original"]
        rel = icon["original"] if icon["format"] == "png" else icon["original"] + ".png"
        target = out_dir / rel
        if not inside(target, pack.derived) or inside(target, pack.original):
            raise VaultError("refusing to write a derivative outside derived/: %s" % rel)
        record: Dict[str, Any] = {"name": icon["name"], "source": "original/" + icon["original"],
                                  "sourceSha256": icon["sha256"], "output": None, "sha256": None,
                                  "action": "skipped", "reason": None, "width": None, "height": None}
        fits = icon["width"] is not None and icon["width"] <= size and icon["height"] <= size
        if icon["format"] == "png" and fits:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                os.chmod(target, stat.S_IMODE(os.stat(target).st_mode) | 0o200)
            shutil.copyfile(source, target)
            record.update(action="copy", width=icon["width"], height=icon["height"])
        elif icon["format"] == "svg":
            record["reason"] = "SVG is not rasterised by this tool; export a PNG from the vector source"
        elif image_module is None:
            record["reason"] = "needs resizing or conversion to PNG, and Pillow is not installed"
        else:
            try:
                with image_module.open(source) as opened:
                    image = opened.convert("RGBA")
                image.thumbnail((size, size), image_module.LANCZOS)
                target.parent.mkdir(parents=True, exist_ok=True)
                image.save(target, format="PNG")
                record.update(action="resize", width=image.width, height=image.height)
            except Exception as error:  # a damaged file must not stop the batch
                record["reason"] = "Pillow could not read it: %s" % error
        if record["action"] != "skipped":
            record["output"] = target.relative_to(pack.dir).as_posix()
            record["sha256"] = sha256_file(target)
        counts[record["action"]] += 1
        entries.append(record)

    sheets_note = "not requested"
    if args.sheets:
        if image_module is None:
            sheets_note = "NOT built: Pillow is not installed"
        else:
            sheets_note = pack_sheets(pack, vault, image_module, size, args.padding, entries)

    manifest_path = pack.derived / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {"schema": SCHEMA, "pack": pack.name, "sizes": {}}
    manifest["sizes"][str(size)] = {
        "generatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "format": "png", "pillow": image_module is not None, "counts": counts, "sheets": sheets_note,
        "entries": entries,
    }
    write_text(manifest_path, dump(manifest), vault)
    print("Derivatives for '%s' at %d px -> %s (originals untouched)" % (pack.name, size, show(out_dir)))
    print("  %d straight copies, %d resized with Pillow, %d skipped" % (counts["copy"], counts["resize"], counts["skipped"]))
    if image_module is None:
        print("  Pillow is not installed: only PNGs that already fit were copied; nothing was resized or converted.")
    reasons: Dict[str, int] = {}
    for record in entries:
        if record["reason"]:
            reasons[record["reason"]] = reasons.get(record["reason"], 0) + 1
    for reason, count in reasons.items():
        print("  skipped %d: %s" % (count, reason))
    print("  sprite sheets: %s" % sheets_note)
    if args.sheets and image_module is None:
        return 1
    return 0


def pack_sheets(pack: Pack, vault: Path, image_module: Any, size: int, padding: int, entries: List[Dict[str, Any]]) -> str:
    """Packs the derived PNGs into 1024 px sheets (cells of size + 2 * padding) with a JSON rect map."""
    cell = size + 2 * padding
    per_row = 1024 // cell
    if per_row < 1:
        return "NOT built: a %d px cell does not fit a 1024 px sheet" % cell
    usable = [e for e in entries if e["output"]]
    if not usable:
        return "NOT built: no derivatives to pack"
    sheet_dir = pack.derived / "sheets"
    sheet_dir.mkdir(parents=True, exist_ok=True)
    for stale in sheet_dir.glob("sheet-*.png"):
        stale.unlink()
    per_sheet = per_row * per_row
    sheets = []
    rects: Dict[str, Any] = {}
    canvas = None
    for index, entry in enumerate(usable):
        number, slot = divmod(index, per_sheet)
        if slot == 0:
            if canvas is not None:
                canvas.save(sheet_dir / ("sheet-%d.png" % number), format="PNG")
            canvas = image_module.new("RGBA", (1024, 1024), (0, 0, 0, 0))
            sheets.append({"file": "derived/sheets/sheet-%d.png" % (number + 1), "width": 1024, "height": 1024})
        with image_module.open(pack.dir / entry["output"]) as opened:
            image = opened.convert("RGBA")
        x = (slot % per_row) * cell + padding + (size - image.width) // 2
        y = (slot // per_row) * cell + padding + (size - image.height) // 2
        canvas.paste(image, (x, y))
        rects[entry["source"][len("original/"):]] = {"name": entry["name"], "sheet": number + 1, "x": x, "y": y,
                                                    "w": image.width, "h": image.height}
    if canvas is not None:
        canvas.save(sheet_dir / ("sheet-%d.png" % len(sheets)), format="PNG")
    for sheet in sheets:
        sheet["sha256"] = sha256_file(pack.dir / sheet["file"])
    write_text(sheet_dir / "sheets.json", dump({"schema": SCHEMA, "pack": pack.name, "size": size, "padding": padding,
                                               "sheets": sheets, "rects": rects}), vault)
    return "%d sheet(s) with %d icons -> %s (run registry again to include the rects)" % (len(sheets), len(usable), show(sheet_dir))


# preview ---------------------------------------------------------------------------------------

PREVIEW = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root{color-scheme:dark;--bg:#14161c;--panel:#1e222b;--line:#323846;--text:#e8ebf2;--dim:#98a1b3;--ok:#4cc38a;--warn:#e5a13a}
*{box-sizing:border-box}body{margin:0;font:14px/1.4 system-ui,sans-serif;background:var(--bg);color:var(--text)}
header{position:sticky;top:0;z-index:2;background:var(--panel);border-bottom:1px solid var(--line);padding:12px 16px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}
h1{font-size:16px;margin:0 12px 0 0}input,select{background:var(--bg);color:var(--text);border:1px solid var(--line);border-radius:8px;padding:8px 10px;font:inherit}
input{flex:1;min-width:180px}.note{color:var(--dim);font-size:12px;width:100%}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(124px,1fr));gap:10px;padding:16px}
button.cell{all:unset;cursor:pointer;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:10px;display:flex;flex-direction:column;align-items:center;gap:6px;text-align:center}
button.cell:hover,button.cell:focus-visible{border-color:#7aa2ff}
.thumb{width:72px;height:72px;display:grid;place-items:center;border-radius:8px;background:repeating-conic-gradient(#2a2f3a 0 25%,#232832 0 50%) 0 0/16px 16px}
.thumb img{max-width:64px;max-height:64px}.name{font-size:12px;word-break:break-word}.meta{font-size:11px;color:var(--dim)}
.ok{color:var(--ok)}.warn{color:var(--warn)}#toast{position:fixed;left:50%;bottom:20px;transform:translateX(-50%);background:#2b6cff;color:#fff;padding:8px 14px;border-radius:999px;opacity:0;transition:opacity .15s}
#toast.on{opacity:1}
</style></head><body>
<header><h1>__TITLE__</h1><input id="q" type="search" placeholder="Search name, tag or category" autofocus>
<select id="cat"><option value="">All categories</option></select>
<select id="ids"><option value="">Any asset-id status</option><option value="mapped">Has asset id</option><option value="missing">Missing asset id</option></select>
<span id="count" class="meta"></span>
<div class="note">Private preview: images load from the originals beside this file, so it only works on this machine. Click an icon to copy its name. __LICENSE__</div></header>
<main id="grid"></main><div id="toast"></div>
<script>
const DATA = __DATA__;
const grid = document.getElementById("grid"), q = document.getElementById("q"), cat = document.getElementById("cat"),
  ids = document.getElementById("ids"), count = document.getElementById("count"), toast = document.getElementById("toast");
for (const c of DATA.categories) { const o = document.createElement("option"); o.value = c; o.textContent = c; cat.appendChild(o); }
function score(icon, query) {
  if (!query) return 1;
  if (icon.name === query) return 100;
  if (icon.name.startsWith(query)) return 60;
  if (icon.name.split("-").includes(query)) return 50;
  if (icon.name.includes(query)) return 40;
  let best = 0;
  for (const t of icon.tags) { if (t === query) best = Math.max(best, 30); else if (t.startsWith(query)) best = Math.max(best, 20); }
  if (!best && icon.category.includes(query)) best = 10;
  return best;
}
function copy(text) {
  const done = () => { toast.textContent = "Copied " + text; toast.classList.add("on"); setTimeout(() => toast.classList.remove("on"), 1200); };
  if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(done, () => window.prompt("Copy the name", text)); }
  else { window.prompt("Copy the name", text); }
}
function render() {
  const query = q.value.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  const rows = DATA.icons.map(i => [score(i, query), i]).filter(([s, i]) => s > 0 && (!cat.value || i.category === cat.value)
    && (!ids.value || (ids.value === "mapped") === Boolean(i.assetId)));
  rows.sort((a, b) => b[0] - a[0] || a[1].name.localeCompare(b[1].name));
  grid.textContent = "";
  for (const [, i] of rows) {
    const cell = document.createElement("button"); cell.className = "cell"; cell.title = i.original;
    const thumb = document.createElement("span"); thumb.className = "thumb";
    const img = document.createElement("img"); img.loading = "lazy"; img.alt = i.name; img.src = i.src; thumb.appendChild(img);
    const name = document.createElement("span"); name.className = "name"; name.textContent = i.name;
    const meta = document.createElement("span"); meta.className = "meta";
    meta.textContent = i.category + " · " + (i.width ? i.width + "×" + i.height : "?") + " · " + i.format;
    const id = document.createElement("span"); id.className = "meta " + (i.assetId ? "ok" : "warn");
    id.textContent = i.assetId ? "id " + i.assetId : "no asset id";
    cell.append(thumb, name, meta, id);
    cell.addEventListener("click", () => copy(DATA.pack + ":" + i.name));
    grid.appendChild(cell);
  }
  count.textContent = rows.length + " of " + DATA.icons.length + " icons";
}
q.addEventListener("input", render); cat.addEventListener("change", render); ids.addEventListener("change", render);
render();
</script></body></html>
"""


def cmd_preview(args: argparse.Namespace) -> int:
    vault = vault_dir(args)
    pack = Pack(vault, args.pack)
    registry = registry_for(pack)
    manifest = pack.manifest()
    out = Path(args.out).expanduser().resolve() if args.out else pack.dir / "preview.html"
    if not inside(out, vault):
        raise VaultError("the preview references the private originals, so it must stay inside the vault: %s" % show(vault))
    base = os.path.relpath(pack.original, out.parent).replace(os.sep, "/")
    icons = [{"name": i["name"], "category": i["category"], "tags": i["tags"], "original": i["original"],
              "format": i["format"], "width": i["width"], "height": i["height"], "assetId": i["assetId"],
              "src": base + "/" + quote(i["original"])} for i in registry["icons"]]
    data = json.dumps({"pack": pack.name, "categories": registry["categories"], "icons": icons}, ensure_ascii=True)
    data = data.replace("</", "<\\/")
    license_note = "Licence: %s." % ("redistributable" if manifest["license"].get("redistributable") else "private, do not share this page or the files")
    title = html.escape("Icon pack: %s (%d icons)" % (pack.name, len(icons)))
    page = PREVIEW.replace("__TITLE__", title).replace("__LICENSE__", html.escape(license_note)).replace("__DATA__", data)
    write_text(out, page, vault)
    print("Preview for '%s': %s (%d icons; open it in a browser on this machine)" % (pack.name, show(out), len(icons)))
    return 0


# CLI -------------------------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--vault", help="vault folder (default: assets/icons/private in the kit)")
    parser = argparse.ArgumentParser(prog="vault.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("import", parents=[common], help="copy a pack byte-for-byte into the vault")
    p.add_argument("source_dir")
    p.add_argument("--name", required=True, help="pack id: lowercase letters, digits, '-'")
    p.add_argument("--license-file", help="the pack's licence file (auto-detected in the source root when omitted)")
    p.add_argument("--license-notes", help="your notes on the licence terms")
    p.add_argument("--redistributable", action="store_true", help="the licence explicitly permits redistribution (needs a licence file)")
    p.add_argument("--force", action="store_true", help="replace vault files that differ from the source")
    p.set_defaults(run=cmd_import)

    p = sub.add_parser("verify", parents=[common], help="re-hash the vault against the manifest (exit 1 on any difference)")
    p.add_argument("pack")
    p.add_argument("--source", help="also compare with the folder the pack was imported from")
    p.add_argument("--json", action="store_true")
    p.set_defaults(run=cmd_verify)

    p = sub.add_parser("registry", parents=[common], help="build registry.json and the Luau data module")
    p.add_argument("pack")
    p.add_argument("--map", help="CSV or JSON of name / original path -> Roblox asset id")
    p.add_argument("--export-map", nargs="?", const="", default=None, metavar="CSV", help="write a CSV template listing every icon")
    p.add_argument("--luau", help="where to write the Luau data module (default: <vault>/<pack>/<Pack>Icons.luau)")
    p.add_argument("--synonyms", help='JSON object of extra tags: { "coin": ["money", "gold"] }')
    p.add_argument("--category-level", choices=["first", "last", "path"], default="first",
                   help="which folder names the category: first (default), last (immediate parent) or the whole path")
    p.add_argument("--rename", action="store_true", help="recompute every name instead of keeping names from the last registry")
    p.add_argument("--force", action="store_true", help="with --export-map: overwrite the default CSV without keeping ids typed into it")
    p.set_defaults(run=cmd_registry)

    p = sub.add_parser("derive", parents=[common], help="optional Roblox-ready copies in derived/<size>/ (never over originals)")
    p.add_argument("pack")
    p.add_argument("--size", type=int, required=True, help="maximum width / height in pixels")
    p.add_argument("--format", choices=["png"], default="png")
    p.add_argument("--sheets", action="store_true", help="also pack sprite sheets into derived/sheets/ (needs Pillow)")
    p.add_argument("--padding", type=int, default=2, help="transparent pixels around each sheet cell (default 2)")
    p.set_defaults(run=cmd_derive)

    p = sub.add_parser("preview", parents=[common], help="write a local HTML gallery")
    p.add_argument("pack")
    p.add_argument("--out", help="output file inside the vault (default: <vault>/<pack>/preview.html)")
    p.set_defaults(run=cmd_preview)

    p = sub.add_parser("search", parents=[common], help="ranked search over names, tags and categories")
    p.add_argument("pack")
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=25)
    p.add_argument("--json", action="store_true")
    p.set_defaults(run=cmd_search)

    p = sub.add_parser("list", parents=[common], help="list icons")
    p.add_argument("pack")
    p.add_argument("--category")
    p.add_argument("--unmapped", action="store_true", help="only icons without an asset id")
    p.add_argument("--json", action="store_true")
    p.set_defaults(run=cmd_list)

    p = sub.add_parser("stats", parents=[common], help="counts by category, size and asset-id status")
    p.add_argument("pack")
    p.add_argument("--json", action="store_true")
    p.set_defaults(run=cmd_stats)

    p = sub.add_parser("autocomplete", parents=[common], help="icon names starting with a prefix (for editors and agents)")
    p.add_argument("pack")
    p.add_argument("prefix", nargs="?", default="")
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--json", action="store_true")
    p.set_defaults(run=cmd_autocomplete)

    p = sub.add_parser("status", parents=[common], help="packs in the vault, verification and asset-id progress")
    p.add_argument("--json", action="store_true")
    p.set_defaults(run=cmd_status)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "run", None):
        parser.print_help()
        return 2
    try:
        return args.run(args)
    except VaultError as error:
        print("vault: %s" % error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
