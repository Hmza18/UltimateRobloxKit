---
name: stylized-asset-design
description: Art direction for polished stylized Roblox assets - chunky proportions, silhouette first, saturated limited palettes, cel-style shading baked into flat textures, outlined chunky titles, consistent bevel and scale across a set, and how to judge renders. Use when deciding how an asset or asset set should look, reviewing art for consistency, or when renders look flat, noisy or realistic when they should not.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [stylized, art style, low poly look, cartoon, chunky, palette, art direction, cel shaded]
  depends: []
---

# Stylized asset design

## Principles (recovered from the supermarket project's design direction)

1. **Silhouette first.** At game distance only shape reads. Exaggerate: thick rims, fat lids, oversized handles. Keep the set's proportions consistent rather than real-world.
2. **No plain blocks.** Every box gets a bevel, rim, band or taper; the crate generator's raised bands are the minimum detail level.
3. **Saturated, limited palette.** 3-5 colours per asset, one dominant. Share a palette across a set so assets belong together.
4. **Cel cues in the texture.** A soft top-to-bottom gradient and a darker outline band per panel (`tools/rbxasset/texture.py`) read as shading under any Roblox lighting.
5. **Chunky outlined type** for any text: heavy rounded fonts, dark outline, high contrast against the panel. Open fonts used in the source project: Lilita One, Fredoka, Nunito (SIL OFL).
6. **No photo textures or baked realism** unless the user asks. The user of the source project explicitly rejected a realistic pass.
7. **Original art only.** No real brands, logos or recognisable trade dress.

## Review checklist (look at the actual renders)

- Does each asset read from the hero angle (yaw 32°, pitch 17°) at 128 px?
- Same bevel size, outline weight and saturation across the set?
- Any text cut by an edge, seam, fold or corner?
- Does anything look like a real product or logo?
- Back and bottom: closed and coloured, not default grey?

## Workflow

1. Write a one-paragraph style brief and a palette (hex) before modelling.
2. Build a sample of three assets, render, compare side by side (contact sheet).
3. Lock the style; then batch.

## Limitations

Taste is not testable; these checks need human or vision review of renders. Automated QA only proves geometry and file correctness.
