---
name: uv-texture-atlas
description: Panel-based UV mapping and texture atlases for Roblox meshes - named panels packed onto one 1024 texture (MaxRects or the fixed 0.75/0.25 product layout), safe printable areas from real geometry, flat stylized painting without Pillow, supplied textures, SurfaceAppearance and PBR map notes, and texel density. Use for UV layout, stretched or clipped labels, wasted texture space, painting textures from code, or sharing one atlas across props.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [uv, uv map, texture atlas, unwrap, safe area, texel density, surfaceappearance, label stretched]
  depends: []
---

# UVs and texture atlases

## How the kit maps UVs

Generators emit faces with UVs in *panel space* (0-1 inside a named panel such as `front`, `wood`, `body`) plus each panel's physical size. `tools/rbxasset/atlas.py` then places panels on the texture:

- `pack(panels, 1024, 12)`: MaxRects, binary-searches the largest uniform texel density that fits; panel `weight` trades resolution between panels.
- `pack_guide(panels, 1024, 6)`: the supermarket layout - front art uv 0-0.75 x 0-1, other panels uv 0.75-1 x 0.25-1, palette corner uv 0.75-1 x 0-0.25.
- `to_texture_uv(uv, rect)` converts to final UVs with a half-pixel inset so samples never bleed into padding.

Set `"layout": "guide"` in a spec to use the product layout; default is `pack`.

## Painting

- Flat stylized: `paint_panels(rects, colors)` + `write_png` (stdlib) give each panel colour, gradient and outline. Colours are keyed by panel name, falling back to the part before `_` (`wood_end` → `wood`).
- Custom art: put a 1024 PNG at `texture` in the spec; the layout's `rects` (in `layout.json`) tell you where each panel sits, in pixels, with `rot` for rotated panels.
- Labels and text: compute printable areas with `safe_area.analyze(verts, faces, panels)` and keep every text box inside them (`element_clear`). Never hand-set margins: folds, tapers and shoulders differ per shape.

## Roblox material notes

- MeshPart `TextureID` = one colour map. For PBR use `SurfaceAppearance` (ColorMap, NormalMap, RoughnessMap, MetalnessMap; set in Studio, not by script at runtime).
- Alpha: only `SurfaceAppearance.AlphaMode = Transparency` shows texture transparency.
- Keep colour maps sRGB, data maps (normal, roughness) non-colour.

## Validation

`asset_batch.py` checks UVs within 0-1 and one UV map. Look at the texture PNG beside the model; text must be unstretched.

## Pitfalls

- Scaling a whole design into the safe area applies margins twice; trim only elements that cross.
- Wave or stripe patterns need a whole number of repeats per panel or they step at the seam.
- Anything crossing a side seam must be drawn on both halves.

## Limitations

No automatic unwrapping of arbitrary imported meshes; for those use Blender's Smart UV Project and then check density by eye.
