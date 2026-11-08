"""rbxasset: Blender-free procedural asset kit for Roblox, recovered from the supermarket pipeline.

Modules
- meshkit: MeshData (lofts, lathes, caps, extrusions) and closed-mesh validation.
- atlas: packs named UV panels onto one texture (generic MaxRects and the 0.75 / 0.25 guide layout).
- safe_area: per-panel printable areas computed from real geometry.
- grid: display-grid maths (cell = spot / cols x spot / rows).
- generators: parameterized generators; `generators.build(spec)` returns a fitted MeshData.
- texture: stdlib PNG writer and flat stylized panel painter (Pillow optional).
- layout: turns a spec into layout.json for scripts/blender/build_asset.py.
"""
__version__ = "1.0.0"
