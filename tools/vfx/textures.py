#!/usr/bin/env python3
"""Generate the kit's original VFX textures. Stdlib only (PNG via zlib + struct).

  python3 tools/vfx/textures.py            # write assets/vfx/textures, flipbooks and manifest.json
  python3 tools/vfx/textures.py --check    # exit 1 if the committed files differ from a fresh build (CI)
  python3 tools/vfx/textures.py --list     # print keys, sizes and descriptions
  python3 tools/vfx/textures.py --only glow,ring --out /tmp/vfx   # a subset, somewhere else

Every texture is white on transparent (transparent pixels keep white RGB, so bilinear filtering never
shows a dark fringe) and is tinted in game by ParticleEmitter.Color, Beam.Color or ImageColor3. Shapes
are drawn by a small supersampled rasteriser: a shape is a function of (x, y) in -1..1 returning
(luminance, alpha), averaged over a grid of sub-samples per pixel.

Output is deterministic: no timestamps, no `random`, noise comes from an integer hash with fixed
seeds. `--check` compares pixels, not file bytes, and tolerates a difference of 1 per channel, so a
different zlib or libm (last-bit rounding in sin/exp) cannot make CI fail.

Asset ids are not produced here. Uploading is a manual step (see assets/vfx/README.md); ids are then
recorded with tools/vfx/assetmap.py, and this tool keeps them when it rebuilds the manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "vfx"
MAX_SIZE = 1024
FLIPBOOK_LAYOUTS = {"Grid2x2": 2, "Grid4x4": 4, "Grid8x8": 8}  # Enum.ParticleFlipbookLayout

# The texture keys Visuals/VFX looks up; `--check` and the tests fail if one is missing.
REQUIRED_KEYS = ("spark", "glow", "star", "ring", "smoke", "circle", "confetti", "coin", "gem", "heart", "leaf",
                 "drop", "shard", "bubble", "flare", "streak", "rays", "gradient_linear", "gradient_radial")

TAU = math.tau


# ---------------------------------------------------------------------------------------------
# PNG
# ---------------------------------------------------------------------------------------------

def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def encode_png(width: int, height: int, pixels: bytes) -> bytes:
    """8-bit RGBA PNG. Each row uses the Up filter when that makes it more compressible (smooth
    gradients shrink a lot); the choice depends only on the pixels, so it is deterministic."""
    stride = width * 4
    assert len(pixels) == stride * height, "pixel buffer does not match the size"
    raw = bytearray()
    previous = bytes(stride)
    for y in range(height):
        row = pixels[y * stride:(y + 1) * stride]
        up = bytes((a - b) & 0xFF for a, b in zip(row, previous))
        if sum(min(v, 256 - v) for v in up) < sum(min(v, 256 - v) for v in row):
            raw += b"\x02" + up
        else:
            raw += b"\x00" + row
        previous = row
    return (b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + _chunk(b"IEND", b""))


def decode_png(data: bytes):
    """(width, height, RGBA bytes) for the PNGs this tool writes (8-bit RGBA, filters 0-4, no interlace)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, header = 8, bytearray(), None
    while pos < len(data):
        length, tag = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    if header is None:
        raise ValueError("PNG has no IHDR")
    width, height, depth, color, _, _, interlace = header
    if (depth, color, interlace) != (8, 6, 0):
        raise ValueError(f"only 8-bit RGBA non-interlaced PNGs are supported (depth {depth}, colour type {color})")
    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    out = bytearray()
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(4, stride):
                row[i] = (row[i] + row[i - 4]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                row[i] = (row[i] + previous[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = row[i - 4] if i >= 4 else 0
                row[i] = (row[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                a = row[i - 4] if i >= 4 else 0
                b = previous[i]
                c = previous[i - 4] if i >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        elif kind != 0:
            raise ValueError(f"unknown PNG filter {kind}")
        out += row
        previous = row
    return width, height, bytes(out)


# ---------------------------------------------------------------------------------------------
# Rasteriser
# ---------------------------------------------------------------------------------------------

def render(shape, width: int, height: int, samples: int = 3) -> bytes:
    """Rasterises `shape(x, y) -> (luminance, alpha)` into RGBA bytes. x runs -1..1 left to right
    and y runs -1..1 top to bottom over the whole image, whatever its aspect. `samples` is the
    supersampling grid per pixel (1 for soft shapes, 3 or 4 for hard edges)."""
    out = bytearray(width * height * 4)
    n = samples * samples
    offsets = [(i + 0.5) / samples for i in range(samples)]
    index = 0
    for py in range(height):
        ys = [(py + o) / height * 2 - 1 for o in offsets]
        for px in range(width):
            lum_sum = alpha_sum = 0.0
            for sy in ys:
                for o in offsets:
                    lum, alpha = shape((px + o) / width * 2 - 1, sy)
                    if alpha > 0:
                        if alpha > 1:
                            alpha = 1.0
                        alpha_sum += alpha
                        lum_sum += lum * alpha
            if alpha_sum > 0:
                value = int(lum_sum / alpha_sum * 255 + 0.5)
                value = 255 if value > 255 else 0 if value < 0 else value
                alpha8 = int(alpha_sum / n * 255 + 0.5)
            else:
                value, alpha8 = 255, 0  # white under full transparency: no dark fringe when filtered
            out[index] = out[index + 1] = out[index + 2] = value
            out[index + 3] = alpha8
            index += 4
    return bytes(out)


def pack_sheet(frames, cell: int, grid: int) -> bytes:
    """Packs grid * grid RGBA frames of `cell` px into one square sheet, left to right, top to
    bottom: the order ParticleEmitter flipbooks play (Grid2x2, Grid4x4, Grid8x8)."""
    if len(frames) != grid * grid:
        raise ValueError(f"a {grid}x{grid} sheet needs {grid * grid} frames, got {len(frames)}")
    side = cell * grid
    sheet = bytearray(side * side * 4)
    for n, frame in enumerate(frames):
        if len(frame) != cell * cell * 4:
            raise ValueError("frame size does not match the cell")
        ox, oy = (n % grid) * cell, (n // grid) * cell
        for y in range(cell):
            start = ((oy + y) * side + ox) * 4
            sheet[start:start + cell * 4] = frame[y * cell * 4:(y + 1) * cell * 4]
    return bytes(sheet)


# ---------------------------------------------------------------------------------------------
# Shape maths
# ---------------------------------------------------------------------------------------------

def clamp01(v: float) -> float:
    return 0.0 if v < 0 else 1.0 if v > 1 else v


def smooth(edge0: float, edge1: float, v: float) -> float:
    """Smoothstep; edge0 > edge1 gives a falling edge."""
    t = clamp01((v - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)


def cover(distance: float, soft: float = 0.012) -> float:
    """Coverage for a signed distance (negative inside) with a `soft` wide edge."""
    return clamp01(0.5 - distance / (2 * soft))


def sd_polygon(points, x: float, y: float) -> float:
    """Signed distance to a closed polygon (negative inside)."""
    best = 1e18
    inside = False
    j = len(points) - 1
    for i in range(len(points)):
        ax, ay = points[j]
        bx, by = points[i]
        ex, ey = bx - ax, by - ay
        wx, wy = x - ax, y - ay
        t = clamp01((wx * ex + wy * ey) / (ex * ex + ey * ey))
        dx, dy = wx - ex * t, wy - ey * t
        d = dx * dx + dy * dy
        if d < best:
            best = d
        if (ay > y) != (by > y) and x < ax + (y - ay) / (by - ay) * ex:
            inside = not inside
        j = i
    d = math.sqrt(best)
    return -d if inside else d


def star_points(tips: int, outer: float, inner: float, rotation: float = -math.pi / 2):
    points = []
    for i in range(tips * 2):
        r = outer if i % 2 == 0 else inner
        a = rotation + i * math.pi / tips
        points.append((math.cos(a) * r, math.sin(a) * r))
    return points


def _hash(ix: int, iy: int, seed: int) -> float:
    """Integer hash -> 0..1. Pure integer maths, so it is identical on every platform."""
    h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / 0xFFFFFF


def value_noise(x: float, y: float, seed: int) -> float:
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    top = _hash(ix, iy, seed) * (1 - ux) + _hash(ix + 1, iy, seed) * ux
    bottom = _hash(ix, iy + 1, seed) * (1 - ux) + _hash(ix + 1, iy + 1, seed) * ux
    return top * (1 - uy) + bottom * uy


def fbm(x: float, y: float, seed: int, octaves: int = 4) -> float:
    """Layered value noise in 0..1."""
    total = amplitude_sum = 0.0
    amplitude, frequency = 1.0, 1.0
    for octave in range(octaves):
        total += value_noise(x * frequency, y * frequency, seed + octave * 101) * amplitude
        amplitude_sum += amplitude
        amplitude *= 0.5
        frequency *= 2.0
    return total / amplitude_sum


# ---------------------------------------------------------------------------------------------
# Shapes: each returns (luminance, alpha) for a point in -1..1
# ---------------------------------------------------------------------------------------------

def glow(x, y):
    r = math.hypot(x, y)
    return 1.0, (1 - r) ** 2.2 if r < 1 else 0.0


def circle(x, y):
    return 1.0, cover(math.hypot(x, y) - 0.9)


def ring(x, y):
    d = abs(math.hypot(x, y) - 0.78) - 0.075
    return 1.0, cover(d, 0.03)


def make_spark(arm: float = 1.0, core: float = 1.0, rotation: float = 0.0):
    """Four-point sparkle: thin crossed arms that fade outward plus a soft core."""
    cos_r, sin_r = math.cos(rotation), math.sin(rotation)

    def spark(x, y):
        rx, ry = x * cos_r + y * sin_r, -x * sin_r + y * cos_r
        ax, ay = abs(rx) / arm, abs(ry) / arm
        d = (ax ** 0.5 + ay ** 0.5) ** 2  # astroid: 1 at the tips, pinched between the arms
        arms = smooth(1.0, 0.25, d)
        r = math.hypot(rx, ry)
        halo = (1 - r / (0.45 * core)) ** 2 * 0.9 if r < 0.45 * core else 0.0
        return 1.0, clamp01(arms + halo)

    return spark


STAR = star_points(5, 0.92, 0.4)


def star(x, y):
    return 1.0, cover(sd_polygon(STAR, x, y) - 0.03)


def flare(x, y):
    """Horizontal lens streak with a hot core; symmetric, for flashes and beams seen side on."""
    along = clamp01(1 - abs(x)) ** 1.6
    across = math.exp(-(y / (0.07 + 0.16 * along)) ** 2)
    r = math.hypot(x * 0.5, y)
    core = (1 - r / 0.5) ** 2 if r < 0.5 else 0.0
    return 1.0, clamp01(along * across + core * 0.8)


def streak(x, y):
    """One-directional speed line: bright head on the right, long tail to the left."""
    u = (x + 1) / 2
    tail = u ** 2.2
    width = 0.12 + 0.5 * u
    across = clamp01(1 - abs(y) / width) ** 1.5
    nose = smooth(1.0, 0.9, u)
    return 1.0, tail * across * nose


def make_smoke(seed: int, growth: float = 1.0, density: float = 1.0):
    """Billowing puff: layered value noise shaped by a radial mask."""
    def smoke(x, y):
        r = math.hypot(x, y) / growth
        if r >= 1:
            return 1.0, 0.0
        n = fbm(x * 2.6 + 11.3, y * 2.6 + 4.7, seed)
        wobble = fbm(x * 5.2 + 3.1, y * 5.2 + 9.9, seed + 57, 3)
        edge = smooth(1.0, 0.25 + 0.35 * wobble, r)
        body = clamp01((n - 0.28) * 2.3)
        return 0.82 + 0.18 * wobble, clamp01(edge * (0.35 + 0.65 * body) * density)

    return smoke


def confetti(x, y):
    """Rounded rectangle; the whole image is 2:1, so the piece is drawn wide."""
    qx, qy = abs(x) - 0.82, abs(y) - 0.72
    d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - 0.1
    return (0.86 if y > 0.15 else 1.0), cover(d, 0.03)


def heart(x, y):
    px, py = x * 1.22, -(y - 0.08) * 1.22 + 0.1
    value = (px * px + py * py - 1) ** 3 - px * px * py ** 3
    return 1.0, 1.0 if value <= 0 else 0.0


def leaf(x, y):
    """Pointed leaf (two crossing circles) leaning 30 degrees, with a darker midrib."""
    c, s = math.cos(-0.52), math.sin(-0.52)
    rx, ry = x * c - y * s, x * s + y * c
    radius, shift = 1.18, 0.72
    d = max(math.hypot(rx - shift, ry) - radius, math.hypot(rx + shift, ry) - radius)
    rib = clamp01(1 - abs(rx) / 0.035) if abs(ry) < 0.8 else 0.0
    return 1.0 - 0.22 * rib, cover(d)


def drop(x, y):
    """Water drop: round belly, pointed top."""
    cy, r, tip = 0.32, 0.56, -0.9
    belly = math.hypot(x, y - cy) - r
    if y < cy:
        t = clamp01((y - tip) / (cy - tip))
        neck = abs(x) - r * t ** 1.08
    else:
        neck = 1.0
    d = min(belly, neck)
    shine = cover(math.hypot((x + 0.2) / 0.5, (y - 0.2) / 1.0) - 0.22, 0.05)
    return 1.0 - 0.14 * (1 - shine), cover(d, 0.015)


SHARD = [(-0.12, -0.95), (0.42, -0.3), (0.26, 0.9), (-0.38, 0.42)]
SHARD_RIDGE = ((-0.12, -0.95), (0.26, 0.9))


def shard(x, y):
    """Crystal splinter with two facets split along its long ridge."""
    (ax, ay), (bx, by) = SHARD_RIDGE
    side = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
    return (1.0 if side > 0 else 0.74), cover(sd_polygon(SHARD, x, y))


def bubble(x, y):
    r = math.hypot(x, y)
    rim = cover(abs(r - 0.82) - 0.05, 0.03)
    body = 0.1 + 0.22 * smooth(0.3, 0.86, r) if r < 0.84 else 0.0
    shine = cover(math.hypot((x + 0.36) / 0.2, (y + 0.4) / 0.13) - 1.0, 0.25)
    glint = cover(math.hypot(x - 0.42, y - 0.44) - 0.05, 0.03) * 0.7
    return 1.0, clamp01(max(rim, body, shine * 0.95, glint))


COIN_STAR = star_points(5, 0.36, 0.16)


def coin(x, y):
    r = math.hypot(x, y)
    lum = 1.0
    if 0.66 < r < 0.74:
        lum = 0.7  # groove inside the rim
    elif r <= 0.66:
        lum = 0.88 - 0.06 * (y + x) / 1.4  # face, a little brighter up and to the left
        emboss = cover(sd_polygon(COIN_STAR, x, y), 0.02)
        lum = lum + (1.0 - lum) * emboss
    return clamp01(lum), cover(r - 0.9)


GEM_OUTLINE = [(-0.5, -0.72), (0.5, -0.72), (0.92, -0.22), (0.0, 0.88), (-0.92, -0.22)]
GEM_FACETS = [
    ([(-0.5, -0.72), (0.5, -0.72), (0.3, -0.22), (-0.3, -0.22)], 1.0),  # table
    ([(-0.5, -0.72), (-0.3, -0.22), (-0.92, -0.22)], 0.8),  # left crown
    ([(0.5, -0.72), (0.92, -0.22), (0.3, -0.22)], 0.9),  # right crown
    ([(-0.92, -0.22), (-0.3, -0.22), (0.0, 0.88)], 0.7),  # left pavilion
    ([(-0.3, -0.22), (0.3, -0.22), (0.0, 0.88)], 0.94),  # centre pavilion
    ([(0.3, -0.22), (0.92, -0.22), (0.0, 0.88)], 0.78),  # right pavilion
]


def gem(x, y):
    d = sd_polygon(GEM_OUTLINE, x, y)
    if d > 0.05:
        return 1.0, 0.0
    lum = 0.85
    for points, shade in GEM_FACETS:
        if sd_polygon(points, x, y) <= 0:
            lum = shade
            break
    return lum, cover(d)


def make_rays(count: int = 12):
    """Ray burst for reward reveals: alternating long and short rays that fade toward the rim."""
    def rays(x, y):
        r = math.hypot(x, y)
        if r >= 1 or r < 1e-6:
            return 1.0, 0.0
        angle = math.atan2(y, x)
        wave = 0.5 + 0.5 * math.cos(angle * count)
        beam = wave ** 5
        long_ray = 0.5 + 0.5 * math.cos(angle * count / 2)
        reach = 0.62 + 0.38 * long_ray
        fade = smooth(reach, reach * 0.25, r) * smooth(0.0, 0.14, r)
        return 1.0, clamp01(beam * fade)

    return rays


def gradient_linear(x, y):
    """Opaque at the top, transparent at the bottom (rotate or flip the ImageLabel as needed)."""
    return 1.0, clamp01((1 - y) / 2)


def gradient_radial(x, y):
    """Linear radial falloff: a softer, wider cousin of `glow` for vignettes and auras."""
    return 1.0, clamp01(1 - math.hypot(x, y))


def trail_fade(x, y):
    """Trail / Beam strip: full on the left, gone on the right, soft top and bottom edges."""
    return 1.0, clamp01((1 - x) / 2) * smooth(1.0, 0.55, abs(y))


def trail_core(x, y):
    """Trail / Beam strip with a hot centre line and a faint sheath."""
    core = math.exp(-(y / 0.22) ** 2)
    sheath = 0.3 * smooth(1.0, 0.3, abs(y))
    return 1.0, clamp01(max(core, sheath)) * clamp01((1 - x) / 2 * 1.4)


def trail_taper(x, y):
    """Trail / Beam strip that narrows to a point on the right."""
    u = (x + 1) / 2
    width = 0.9 * (1 - u) ** 0.8
    if width <= 0:
        return 1.0, 0.0
    return 1.0, clamp01((1 - abs(y) / width) * 3) * (1 - 0.5 * u)


# key, file size (w, h), supersampling, shape, description
TEXTURES = [
    ("spark", (128, 128), 2, make_spark(), "Four-point sparkle with a soft core. The default twinkle particle."),
    ("glow", (128, 128), 1, glow, "Soft radial glow, brightest at the centre, fully transparent at the rim."),
    ("star", (128, 128), 3, star, "Solid five-point star with slightly rounded tips."),
    ("ring", (128, 128), 2, ring, "Thin soft-edged ring for shockwaves and pulses."),
    ("smoke", (128, 128), 1, make_smoke(7), "Billowing smoke puff from layered value noise (fixed seed)."),
    ("circle", (128, 128), 3, circle, "Hard-edged disc for dots, bokeh and chunky cartoon particles."),
    ("confetti", (64, 32), 3, confetti, "Rounded confetti strip with a folded shade; spin it with RotSpeed."),
    ("coin", (128, 128), 3, coin, "Coin disc with a rim groove and an embossed star; tint it gold."),
    ("gem", (128, 128), 3, gem, "Faceted diamond with six shaded facets; tint it per currency or rarity."),
    ("heart", (128, 128), 4, heart, "Solid heart for pet affection and likes."),
    ("leaf", (128, 128), 3, leaf, "Pointed leaf with a midrib for falling-leaf and nature effects."),
    ("drop", (128, 128), 3, drop, "Water drop with a soft inner highlight for splashes and rain."),
    ("shard", (128, 128), 3, shard, "Two-facet crystal splinter for breaks, ice and egg cracks."),
    ("bubble", (128, 128), 2, bubble, "Bubble: thin rim, faint body and a highlight."),
    ("flare", (256, 64), 1, flare, "Horizontal lens streak with a hot core for flashes and impacts."),
    ("streak", (256, 64), 1, streak, "One-directional speed line: bright head, long fading tail."),
    ("rays", (256, 256), 1, make_rays(), "Twelve-ray burst with alternating lengths for reward reveals."),
    ("gradient_linear", (32, 128), 1, gradient_linear, "Vertical alpha ramp, opaque at the top."),
    ("gradient_radial", (128, 128), 1, gradient_radial, "Linear radial falloff for vignettes and auras."),
    ("trail_fade", (256, 32), 1, trail_fade, "Trail or Beam strip that fades along its length."),
    ("trail_core", (256, 32), 1, trail_core, "Trail or Beam strip with a hot centre line."),
    ("trail_taper", (256, 32), 1, trail_taper, "Trail or Beam strip that tapers to a point."),
]


def twinkle_frames(cell: int):
    """16 frames: a sparkle that swells, flashes and shrinks while turning an eighth of a turn."""
    frames = []
    for n in range(16):
        t = n / 15
        pulse = math.sin(t * math.pi)
        frames.append(render(make_spark(0.25 + 0.75 * pulse, 0.4 + 0.6 * pulse, t * math.pi / 4), cell, cell, 2))
    return frames


def puff_frames(cell: int):
    """4 frames: a smoke puff that grows and thins out."""
    return [render(make_smoke(7, 0.55 + 0.15 * n, 1 - 0.22 * n), cell, cell, 1) for n in range(4)]


def pulse_frames(cell: int):
    """16 frames: a ring that expands from the centre and fades, for looping shockwaves."""
    frames = []
    for n in range(16):
        t = n / 15
        radius, width, fade = 0.12 + 0.76 * t, 0.1 - 0.06 * t, 1 - t ** 1.5

        def shape(x, y, radius=radius, width=width, fade=fade):
            return 1.0, cover(abs(math.hypot(x, y) - radius) - width, 0.035) * fade

        frames.append(render(shape, cell, cell, 2))
    return frames


# key, layout, cell size, frame builder, description
FLIPBOOKS = [
    ("sparkle_twinkle", "Grid4x4", 64, twinkle_frames, "Sparkle that swells, flashes and shrinks while turning."),
    ("puff_dissolve", "Grid2x2", 128, puff_frames, "Smoke puff that grows and thins out over four frames."),
    ("ring_pulse", "Grid4x4", 64, pulse_frames, "Ring expanding from the centre and fading; loops cleanly."),
]


# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------

def is_power_of_two(n: int) -> bool:
    return n > 0 and n & (n - 1) == 0


def build(only=None):
    """Renders everything (or the keys in `only`). Returns ordered {relative path: (entry, pixels)}."""
    results = {}
    for key, (width, height), samples, shape, description in TEXTURES:
        if only and key not in only:
            continue
        assert is_power_of_two(width) and is_power_of_two(height) and max(width, height) <= MAX_SIZE, key
        pixels = render(shape, width, height, samples)
        entry = {"key": key, "kind": "texture", "file": f"textures/{key}.png", "size": [width, height],
                 "description": description}
        results[entry["file"]] = (entry, pixels)
    for key, layout, cell, frames, description in FLIPBOOKS:
        if only and key not in only:
            continue
        grid = FLIPBOOK_LAYOUTS[layout]
        side = cell * grid
        assert is_power_of_two(side) and side <= MAX_SIZE, key
        pixels = pack_sheet(frames(cell), cell, grid)
        entry = {"key": key, "kind": "flipbook", "file": f"flipbooks/{key}.png", "size": [side, side],
                 "layout": layout, "frames": grid * grid, "frameSize": [cell, cell], "description": description}
        results[entry["file"]] = (entry, pixels)
    return results


def load_manifest(out_dir: Path):
    path = out_dir / "manifest.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def manifest_for(results, files, previous):
    """The manifest for a build. `files` maps relative path -> PNG bytes; asset ids recorded in the
    previous manifest are kept, so rebuilding never loses an upload."""
    known = {}
    if previous:
        for group in ("textures", "flipbooks"):
            for item in previous.get(group, []):
                known[item["key"]] = item.get("assetId")
    manifest = {
        "_doc": "Generated by tools/vfx/textures.py. Do not edit by hand, except through tools/vfx/assetmap.py "
                "which fills assetId after a manual upload.",
        "version": 1,
        "license": "MIT",
        "generator": "tools/vfx/textures.py",
        "textures": [],
        "flipbooks": [],
    }
    for rel, (entry, pixels) in results.items():
        item = dict(entry)
        item["bytes"] = len(files[rel])
        item["sha256"] = hashlib.sha256(files[rel]).hexdigest()
        item["pixelSha256"] = hashlib.sha256(pixels).hexdigest()
        item["assetId"] = known.get(entry["key"])
        manifest["textures" if entry["kind"] == "texture" else "flipbooks"].append(item)
    return manifest


def dump_manifest(manifest) -> str:
    return json.dumps(manifest, indent=2) + "\n"


def write(out_dir: Path, results) -> int:
    files = {rel: encode_png(entry["size"][0], entry["size"][1], pixels) for rel, (entry, pixels) in results.items()}
    for rel, data in files.items():
        path = out_dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (out_dir / "manifest.json").write_text(dump_manifest(manifest_for(results, files, load_manifest(out_dir))),
                                           encoding="utf-8")
    return sum(len(data) for data in files.values())


def pixels_match(a: bytes, b: bytes, tolerance: int = 1) -> bool:
    if a == b:
        return True
    return len(a) == len(b) and all(abs(x - y) <= tolerance for x, y in zip(a, b))


def check(out_dir: Path, results) -> list:
    """Problems that make the committed output stale; an empty list means current."""
    problems = []
    manifest = load_manifest(out_dir)
    if manifest is None:
        return [f"missing {out_dir / 'manifest.json'}"]
    listed = {item["file"]: item for group in ("textures", "flipbooks") for item in manifest.get(group, [])}
    keys = {item["key"] for item in listed.values()}
    for key in REQUIRED_KEYS:
        if key not in keys:
            problems.append(f"manifest lacks the required key {key}")
    for rel in listed:
        if rel not in results:
            problems.append(f"{rel} is in the manifest but no longer generated")
    for rel, (entry, pixels) in results.items():
        path = out_dir / rel
        item = listed.get(rel)
        if item is None:
            problems.append(f"{rel} is not in the manifest")
            continue
        if not path.exists():
            problems.append(f"missing {rel}")
            continue
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item.get("sha256") or len(data) != item.get("bytes"):
            problems.append(f"{rel} does not match the hash in the manifest")
        try:
            width, height, committed = decode_png(data)
        except (ValueError, zlib.error, struct.error) as err:
            problems.append(f"{rel} is not a readable PNG: {err}")
            continue
        if [width, height] != entry["size"] or not pixels_match(committed, pixels):
            problems.append(f"{rel} differs from a fresh render")
        for field, value in entry.items():
            if item.get(field) != value:
                problems.append(f"{rel}: manifest field {field} is stale")
    on_disk = {p.relative_to(out_dir).as_posix() for folder in ("textures", "flipbooks")
               for p in (out_dir / folder).glob("*.png")}
    for rel in sorted(on_disk - set(results)):
        problems.append(f"{rel} is on disk but not generated (delete it)")
    return problems


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="verify the committed files instead of writing")
    ap.add_argument("--list", action="store_true", help="print keys, sizes and descriptions")
    ap.add_argument("--only", help="comma-separated keys to build (not with --check)")
    ap.add_argument("--out", type=Path, default=OUT, help="output folder (default assets/vfx)")
    a = ap.parse_args(argv)

    if a.list:
        for key, (width, height), _, _, description in TEXTURES:
            print(f"{key:18} {width}x{height:<5} {description}")
        for key, layout, cell, _, description in FLIPBOOKS:
            side = cell * FLIPBOOK_LAYOUTS[layout]
            print(f"{key:18} {side}x{side:<5} {layout}, {description}")
        return 0

    only = None
    if a.only:
        only = {k.strip() for k in a.only.split(",") if k.strip()}
        known = {t[0] for t in TEXTURES} | {f[0] for f in FLIPBOOKS}
        unknown = sorted(only - known)
        if unknown:
            print(f"unknown texture key(s): {', '.join(unknown)}", file=sys.stderr)
            return 2
        if a.check:
            print("--only cannot be combined with --check", file=sys.stderr)
            return 2

    results = build(only)
    if a.check:
        problems = check(a.out, results)
        for problem in problems:
            print(f"stale: {problem}")
        if problems:
            print("run: python3 tools/vfx/textures.py")
            return 1
        print(f"vfx textures are current ({len(results)} files)")
        return 0

    total = write(a.out, results)
    try:
        shown = a.out.resolve().relative_to(ROOT)
    except ValueError:
        shown = a.out
    print(f"wrote {len(results)} PNGs ({total} bytes) and manifest.json to {shown}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
