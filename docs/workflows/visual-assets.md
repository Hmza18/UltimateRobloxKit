# Workflow: visual effect assets

The visuals kit works with no uploaded assets: effects use Roblox's built-in particle textures. This workflow replaces them with the kit's own textures, which look sharper and give each effect its proper shape (stars, rings, coins, hearts, ray bursts).

```
tools/vfx/textures.py ─▶ assets/vfx/textures/*.png, flipbooks/*.png, manifest.json
tools/vfx/preview.py  ─▶ build/vfx/preview.html (look at them)
you                   ─▶ upload the PNGs with your Roblox account
tools/vfx/assetmap.py ─▶ manifest.json gets the asset ids, VfxTextures.luau is written
your game             ─▶ Visuals.Configure({ textures = require(VfxTextures) })
```

Everything here is stdlib Python. Nothing uploads, downloads or signs in.

## 1. Generate

The textures are committed, so this step is only needed after changing a shape.

```bash
python3 tools/vfx/textures.py
```

```bash
python3 tools/vfx/textures.py --check
```

`--check` re-renders everything and exits 1 if a committed file differs, the same way the icon builder does. It compares pixels with a tolerance of 1 per channel, so a different zlib or maths library on another machine does not cause a false failure. `--list` prints the keys, and `--only glow,ring --out <dir>` builds a subset somewhere else.

To add a texture, write a shape function in `tools/vfx/textures.py` that maps a point in -1..1 to `(luminance, alpha)`, add a row to `TEXTURES`, rebuild, and add the key to the table in [assets/vfx/README.md](../../assets/vfx/README.md). Keep shapes white: colour comes from the emitter.

## 2. Preview

```bash
python3 tools/vfx/preview.py
```

This writes `build/vfx/preview.html` (git-ignored): each texture on a dark background, its silhouette on a light one and a tinted copy, with flipbooks playing at 12 fps. Pass `--tint "#33CCFF"` for another tint. It is a browser approximation for checking shapes and edges, not Roblox rendering.

## 3. Upload (manual)

Upload with the account or group that owns the game, so the game is allowed to use the images:

1. In Studio, open the Asset Manager and use bulk import on `assets/vfx/textures/*.png` and `assets/vfx/flipbooks/*.png`. Creator Hub's upload page for images works too.
2. Wait for moderation to finish.
3. Copy each image's asset id.

The kit cannot do this for you and does not try. Whether moderation accepts every image is `NEEDS MANUAL REVIEW`: none of them has been uploaded.

## 4. Map the ids

Write a template, fill in the `assetId` column, and apply it:

```bash
python3 tools/vfx/assetmap.py template --out vfx-ids.csv
```

```bash
python3 tools/vfx/assetmap.py apply vfx-ids.csv --out src/shared/VfxTextures.luau
```

```bash
python3 tools/vfx/assetmap.py status
```

`apply` accepts `1234567890`, `rbxassetid://1234567890` or an asset URL, and refuses the whole file if any row has a malformed id, an unknown key or an id used twice. A blank cell leaves that key as it was. It checks the shape of an id only: it has no way to confirm the id is the image you meant, so look at one effect in Studio after mapping.

`apply` writes the ids into `assets/vfx/manifest.json` (rebuilding the textures later keeps them) and emits a Luau module:

```lua
return {
	spark = "rbxassetid://1234567891",
	glow = "rbxassetid://1234567890",
} :: { [string]: string }
```

Use `--format json` for a JSON template and `--dry-run` to validate without touching the manifest. To keep a per-game copy of the manifest instead of editing the kit's, pass `--manifest <path>` before the subcommand: `python3 tools/vfx/assetmap.py --manifest my-game/vfx-manifest.json apply vfx-ids.csv`.

## 5. Use

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
local VfxTextures = require(ReplicatedStorage.Shared.VfxTextures)

Visuals.Configure({ textures = VfxTextures })
```

Keys that are not in the map keep using the built-in textures, so a partial upload is fine. Flipbook sheets need the emitter's `FlipbookLayout` to match the sheet: `sparkle_twinkle` and `ring_pulse` are `Enum.ParticleFlipbookLayout.Grid4x4`, `puff_dissolve` is `Grid2x2`. The layout of each sheet is in the manifest and in the header of the generated module.

## Effect meshes (documented path, not implemented)

Some effects read better as geometry than as particles: a shockwave disc that scales outward, a lens that flashes, shards that fly apart. The kit has no generator for these yet. This is how they can be built with the existing asset pipeline ([Blender assets](blender-assets.md)), and what was and was not checked.

`tools/rbxasset/meshkit.py` already has the primitives:

| Mesh | Call | Checked |
|---|---|---|
| Shockwave disc | `MeshData().loft(lathe_rings([(1.0, 0), (1.0, 0.05)], 24), "side")` | Closed, outward normals, 92 triangles (`meshkit.validate`) |
| Lens / energy disc | `MeshData().loft(lathe_rings([(0.6, 0), (1.0, 0.04), (0.6, 0.08)], 24), ["side", "side"])` | Closed, outward normals, 140 triangles |
| Shard | `MeshData().extrude([(-0.12, -0.95), (0.42, -0.3), (0.26, 0.9), (-0.38, 0.42)], 0, 0.2)` | Closed, outward normals, 12 triangles |

Those three calls were run once against `meshkit.validate` while writing this page. They are not in the repository as generators, they have no tests, and they were not built in Blender, exported or imported into Studio.

To turn one into an asset:

1. Add a function to a module in `tools/rbxasset/generators/` with the signature `name(w, d, h, **params)` that returns a `MeshData`, and list it in that module's `GENERATORS`.
2. Reference it from a batch spec (`"generator": "shockwave_disc", "size": [4, 4, 0.2]`) and run `python3 scripts/export/asset_batch.py <spec> --out build/fx`.
3. Import the FBX into Studio as a MeshPart, set it to `CanCollide = false`, `Anchored = true`, `CastShadow = false`, and animate `Size` and `Transparency` with the visuals kit.

Known gap: a true ring with a hole (an annulus) cannot be made with `loft` or `extrude`, because both cap their ends. It needs a loft between an inner and an outer ring without caps, which `meshkit` does not offer today. Until then use the `ring` texture on a flat part, a Beam, or a particle.
