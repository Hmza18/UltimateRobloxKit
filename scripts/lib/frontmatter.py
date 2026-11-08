"""Parser for the restricted SKILL.md frontmatter subset (see docs/architecture/skill-format.md).

Supports `key: value`, double- or single-quoted scalars, inline lists `[a, b]`, and one level of
nested maps by two-space indentation. Anything else raises ValueError, so malformed skills fail
tests instead of being silently misread.
"""
from __future__ import annotations

from pathlib import Path


def _scalar(raw: str):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        return raw[1:-1]
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        return [_scalar(x) for x in _split_list(inner)] if inner else []
    return raw


def _split_list(inner: str):
    items, cur, quote = [], "", None
    for ch in inner:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote, cur = ch, cur + ch
        elif ch == ",":
            items.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        items.append(cur.strip())
    return items


def parse(text: str):
    """Return (frontmatter dict, body str)."""
    if not text.startswith("---\n"):
        raise ValueError("SKILL.md must start with '---' frontmatter")
    end = text.find("\n---", 4)
    if end < 0:
        raise ValueError("unterminated frontmatter")
    block, body = text[4:end], text[end + 4:].lstrip("\n")
    data, current = {}, None
    for n, line in enumerate(block.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if ":" not in line:
            raise ValueError(f"frontmatter line {n}: expected 'key: value'")
        key, _, value = line.strip().partition(":")
        key = key.strip()
        if indent == 0:
            if value.strip() == "":
                data[key] = current = {}
            else:
                data[key], current = _scalar(value), None
        elif indent == 2 and current is not None:
            current[key] = _scalar(value)
        else:
            raise ValueError(f"frontmatter line {n}: unsupported indentation")
    return data, body


def load(path):
    return parse(Path(path).read_text(encoding="utf-8"))
