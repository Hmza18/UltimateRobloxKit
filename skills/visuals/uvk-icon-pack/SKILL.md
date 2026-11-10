---
name: uvk-icon-pack
description: Integrating a purchased or private icon pack with UltimateVisualsKit - the vault tool that imports a pack byte-for-byte without altering it, verifies it by SHA-256, builds a searchable registry and a Luau data module, maps Roblox asset ids after the owner's manual upload, and the Visuals.Icons runtime (register, apply, themed and animated containers, picker, UrkUI bridge), with the licence rules that keep paid files out of git. Use when importing my icon pack, a paid or third-party icon pack, mapping icon asset ids, or using pack icons by name in UI.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [icon pack, import my icon pack, paid icon pack, private icons, icon vault, icon registry, icon asset ids, pack icons, purchased icons, vault.py]
  depends: [uvk-visuals-kit]
---

# UVK icon pack integration

## When to use

- The owner has an icon pack (bought, commissioned or otherwise licensed) and wants its icons in the game.
- Finding a pack icon by name, mapping uploaded asset ids, or showing pack icons in components.

When not to use: drawing new icons or using the kit's own MIT icons (`roblox-icon-design`); deciding whether an asset may be used at all (`asset-sourcing-licensing`).

## Inputs

- The unzipped pack in a folder outside the repository, and its licence file.
- A short pack id (lowercase letters, digits and `-`), written `mypack` below.
- Later: the Roblox asset ids from the owner's upload.

## Workflow

1. **Read the licence first.** May the icons be used in a published game? May the files be redistributed? Is attribution required? The default is private: `redistributable: false`. Leave it unless the licence explicitly allows redistribution.

2. **See what is there.**

   ```bash
   python3 $URK/urk.py visuals icons status
   ```

3. **Import and verify.** Originals are copied byte-for-byte into the git-ignored vault and made read-only. Nothing is redrawn, recoloured, renamed, resized or re-encoded.

   ```bash
   python3 $URK/tools/icons/vault.py import ~/Downloads/MyIconPack --name mypack --license-file ~/Downloads/MyIconPack/LICENSE.txt
   ```

   ```bash
   python3 $URK/tools/icons/vault.py verify mypack --source ~/Downloads/MyIconPack
   ```

   `OK` means every file matches the manifest and the source folder. Any other line exits 1.

4. **Build the registry and look.**

   ```bash
   python3 $URK/tools/icons/vault.py registry mypack --export-map
   ```

   ```bash
   python3 $URK/tools/icons/vault.py search mypack sword --limit 10
   ```

   This writes `registry.json`, the game data module `MypackIcons.luau` (names, categories, tags, sizes and asset ids only; no image data) and an `asset-map.csv` template. `preview mypack` writes a local HTML gallery; it links to the private originals, so do not share it.

5. **Upload is manual.** Uploading images needs the owner's signed-in Roblox account (Studio Asset Manager or Creator Hub), and Roblox moderates every image. Never attempt it, and never ask for credentials. Optional Roblox-ready copies go to `derived/`, never over originals: `vault.py derive mypack --size 256` (resizing needs Pillow).

6. **Map the asset ids** the owner sends back, then check what is missing.

   ```bash
   python3 $URK/tools/icons/vault.py registry mypack --map assets/icons/private/mypack/asset-map.csv
   ```

   ```bash
   python3 $URK/tools/icons/vault.py list mypack --unmapped
   ```

7. **Use the icons in the game.** Copy `MypackIcons.luau` into the project and register it once on the client.

   ```lua
   local Icons = Visuals.Icons
   Icons.register("mypack", require(ReplicatedStorage.Shared.MypackIcons))
   Icons.bridge()                                    -- "mypack:sword" now works in UrkUI components and screen specs

   Icons.apply(imageLabel, "mypack:sword")           -- the pack icon, in its own colours
   local tile = Icons.container("mypack:sword", { size = 72, palette = "purple", parent = row })
   local gem = Icons.animated("mypack:gem", "Pulse", { parent = hud })
   local picker = Icons.picker({ parent = playerGui, onPick = function(id) print(id) end })

   for _, name in Icons.missingAssetIds("mypack") do
   	warn("not uploaded yet:", name)
   end
   ```

   `"pack:name"` is exact. A bare name is looked up in the default pack, then other packs, then the kit icons. `Icons.search(query)` ranks by name, tags and category.

8. **Refer to icons only by `pack:name`** in tracked code and docs. Theme the container, not the icon: pack icons keep their own colours unless `tint` is passed.

## Outputs

- A verified pack in the private vault (untracked), a registry, a Luau data module in the game, and a list of icons still without asset ids.

## Validation

```bash
python3 $URK/tools/icons/vault.py verify mypack
```

```bash
git status --short assets/icons/private
```

The second command must list nothing but the tracked README. In the kit repository the tool and the registry logic are tested by `tests/test_visuals_icons.py` and `cd library && lune run tests/run tests visuals_icons`. How icons look in game, the picker and the bridge are `NEEDS MANUAL REVIEW` in Studio.

## Pitfalls

- **Committing paid files.** Never `git add -f` anything under the vault, never copy originals, derived images, previews, manifests or registries into tracked folders, and never paste their contents into docs. The licence decides, and the default answer is no.
- **"Improving" the icons.** Do not recolour, redraw, trace, upscale or re-export originals. Derivatives are separate and recorded.
- **Hard-coding asset ids** in UI code. Ids live in the data module; code uses names.
- **Trusting spec validation for pack icons.** Screen specs accept `icon = "mypack:sword"` by shape only: no validator knows whether the pack is registered, the HTML preview draws a labelled tile instead of the artwork, and an unregistered pack icon shows nothing in game. Register the pack and call `bridge()` before building the screen.
- **Capturing `Icons.apply` in a local before `bridge()`** keeps the old function.
- **Reading the pack's name or file list into public text** (commit messages, PRs, issue comments). Keep it generic.

## Limitations

- Nothing is uploaded and no asset id is created by the kit; until the owner uploads and maps ids, pack icons fall back or show nothing.
- `IconVaultLogic` is covered by a Lune spec and the vault tool by Python tests against a synthetic fixture. `IconVault.luau` (apply, container, animated, picker, bridge) was not run in Studio.
- SVG is not rasterised by the tool. Without Pillow, `derive` only makes straight copies and reports what it skipped.
