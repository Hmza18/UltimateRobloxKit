# Importing a paid icon pack

**Status: the pack import is pending.** The pipeline below is built and tested against a synthetic fixture pack, but the owner's paid icon pack (about 800 icons) has not been supplied yet. Until it is, this reports the pending state:

```bash
python3 tools/icons/vault.py status
```

When the files arrive, the import is one command (step 2). Nothing here uploads anything to Roblox, and no Studio behaviour described here has been exercised: every in-game step is `NEEDS MANUAL REVIEW`.

## What the tool guarantees

- **Originals are never altered.** Every file is copied byte-for-byte with its relative path and file name unchanged. No redrawing, recolouring, renaming, resizing, compression, re-encoding or metadata stripping. Formats and transparency are whatever the pack shipped.
- **Integrity is provable.** Each file's SHA-256 is recorded in `manifest.json` and in a `sha256sum`-compatible `SHA256SUMS`. `verify` re-hashes everything and exits 1 on any difference. The vault copies are made read-only.
- **Private by default.** The vault is git-ignored, and `import` refuses to copy into a place git would track.
- **Derivatives are separate.** Anything resized or packed for Roblox goes to `derived/`, never over an original.
- **Nothing is deleted.** Re-importing never removes a file from the vault, and it refuses to replace a file whose content differs unless you pass `--force`.

## Licence checklist (do this first)

1. Read the pack's licence. Find the answers to: may the icons be used in a published game, may the files be redistributed (for example in a public repository or a template you sell), is attribution required, is the licence per seat or per project?
2. Keep the licence file. `import` copies it into the pack folder and records its hash.
3. The default is **private**: `redistributable: false`. Leave it that way unless the licence explicitly permits redistribution.
4. `--redistributable` (which needs a licence file) records `redistributable: true` and lets `import` write to a location git would track. It does not un-ignore anything: files under `assets/icons/private/` stay ignored until you deliberately change `.gitignore` or force-add them. Do that only if the licence says you may.
5. Using icons in a published Roblox game means uploading them to Roblox under your account. Check that the licence allows that use.
6. If the licence requires attribution, add it to your game's credits and to `SOURCES.md`.

## Steps

### 1. Check the starting state

```bash
python3 tools/icons/vault.py status
```

It prints `Icon pack import: PENDING` until a pack is in the vault.

### 2. Import

Unzip the pack somewhere outside the repository, then:

```bash
python3 tools/icons/vault.py import ~/Downloads/MyIconPack --name mypack --license-file ~/Downloads/MyIconPack/LICENSE.txt
```

`--name` is the pack id used everywhere afterwards (lowercase letters, digits and `-`). When `--license-file` is omitted, a `LICENSE*`, `EULA*` or `TERMS*` file in the source root is picked up automatically. Add `--license-notes "..."` to record your reading of the terms.

The summary shows how many files were copied, the formats found and the licence state. Running the same command again copies nothing (identical files are skipped).

### 3. Verify

```bash
python3 tools/icons/vault.py verify mypack --source ~/Downloads/MyIconPack
```

`OK` means every vault file matches the manifest and the folder you imported from. Any `MISSING`, `EXTRA`, `MODIFIED`, `SOURCE-ONLY`, `VAULT-ONLY` or `DIFFERS-FROM-SOURCE` line makes the command exit 1. Run `verify mypack` (without `--source`) any time later to prove the originals are still intact.

### 4. Build the registry

```bash
python3 tools/icons/vault.py registry mypack --export-map
```

This reads the manifest (never the image contents) and writes:

| File | What |
|---|---|
| `registry.json` | one entry per icon: `name`, `category`, `subcategory`, `tags`, `original` path, `sha256`, `bytes`, `format`, `width`, `height`, `assetId` |
| `MypackIcons.luau` | the game data module: names, categories, tags, sizes and asset ids only |
| `asset-map.csv` | a template listing every icon, with an empty `assetId` column |

Naming rules: the file stem becomes kebab-case (`Sword_Icon 02.png` becomes `sword-icon-02`). The first folder is the category (`--category-level last` or `path` changes that). When two files would get the same name, both get the category as a prefix, then the folder path, then the format, then a number. The original path is always kept beside the name. Names already assigned stay the same when you add files later; `--rename` recomputes them all. `--synonyms words.json` adds search tags, for example `{ "coin": ["money", "gold"] }`.

Look at the result:

```bash
python3 tools/icons/vault.py preview mypack
```

```bash
python3 tools/icons/vault.py stats mypack
```

`preview` writes `preview.html` in the vault: search box, category filter, asset-id filter, click to copy `mypack:name`. It links to the private originals by relative path, so it only works on your machine and must not be shared.

### 5. Upload to Roblox (manual)

Uploading images requires your signed-in Roblox account, so the kit does not attempt it. Upload the icons you need with Studio's Asset Manager (bulk import) or Creator Hub, under the account or group that owns the game. Roblox moderates every image, and images larger than 1024 x 1024 are scaled down by Roblox.

If the originals are SVG or larger than you want, make Roblox-ready copies first (optional):

```bash
python3 tools/icons/vault.py derive mypack --size 256
```

`derive` writes to `derived/256/` and records each output with the SHA-256 of its source in `derived/manifest.json`. PNGs that already fit are straight copies. Resizing and conversion to PNG need Pillow (`python3 -m pip install pillow`); without it those icons are reported as skipped, and nothing is claimed. SVG is not rasterised: export PNGs from the vector source. Add `--sheets` (Pillow) to pack sprite sheets into `derived/sheets/` with a `sheets.json` rect map, then run `registry` again so the rects reach the Luau module.

### 6. Map the asset ids

Fill the `assetId` column of `assets/icons/private/mypack/asset-map.csv` (a number, `rbxassetid://123` or a Creator Hub URL all work), then:

```bash
python3 tools/icons/vault.py registry mypack --map assets/icons/private/mypack/asset-map.csv
```

A JSON file works too: `{ "sword": 123, "Weapons/Shield.png": 456 }`. Sprite sheets are mapped with the name `@sheet-1`, `@sheet-2`. Ids are kept when the registry is rebuilt. See what is still missing:

```bash
python3 tools/icons/vault.py list mypack --unmapped
```

### 7. Use the icons in the game

Copy `MypackIcons.luau` into your game (it holds no image data) and register it once on the client:

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
local Icons = Visuals.Icons

Icons.register("mypack", require(ReplicatedStorage.Shared.MypackIcons))

Icons.apply(imageLabel, "mypack:sword")           -- the pack icon, in its own colours
Icons.apply(imageLabel, "coin")                    -- not in a pack: the kit's own icon
local tile = Icons.container("mypack:sword", { size = 72, palette = "purple", parent = row })
local gem = Icons.animated("mypack:gem", "Pulse", { parent = hud })
local picker = Icons.picker({ parent = playerGui, onPick = function(id) print(id) end })
```

Pack icons keep their own colours: `ImageColor3` stays white unless you pass `tint`. Theming comes from the container (background, gradient and outline follow the active UrkUI style), and animation moves the container Frame.

To use pack icons by name in UrkUI components and screen specs (`icon = "mypack:sword"`), call `Icons.bridge()` once after registering. Details and limits are in [the Icons module README](../../library/src/Visuals/Icons/README.md).

## Where files live

```
assets/icons/private/                 git-ignored except README.md
  README.md
  mypack/
    original/...                      the untouched pack, read-only
    manifest.json                     SHA-256, size, format, dimensions per file; licence record
    SHA256SUMS                        sha256sum -c compatible
    license/<licence file>            copy of the licence
    registry.json                     names, categories, tags, asset ids
    asset-map.csv                     asset-id template / map
    MypackIcons.luau                  data module for the game
    preview.html                      local gallery
    derived/<size>/...                optional Roblox-ready copies
    derived/sheets/                   optional sprite sheets + sheets.json
    derived/manifest.json             every derivative with its source hash
```

`.gitignore` holds `assets/icons/private/*` and `!assets/icons/private/README.md`, so everything a pack produces stays out of git. Pass `--vault <dir>` to keep the vault somewhere else; `import` then checks that location with `git check-ignore`.

`MypackIcons.luau` lists icon names and asset ids only. Committing a copy inside your own game project is your decision; check the licence if the names themselves are part of what you bought.

## Commands

| Command | Purpose |
|---|---|
| `status [--json]` | packs found, verification state, asset-id progress; `PENDING` when there is none |
| `import <source_dir> --name <pack> [--license-file f] [--license-notes t] [--redistributable] [--force]` | byte-for-byte copy into the vault |
| `verify <pack> [--source dir] [--json]` | integrity proof; exit 1 on any difference |
| `registry <pack> [--map csv/json] [--export-map [csv]] [--luau out] [--synonyms json] [--category-level first/last/path] [--rename]` | registry, Luau module, asset-id template |
| `derive <pack> --size <px> [--format png] [--sheets] [--padding n]` | optional derivatives |
| `preview <pack> [--out html]` | local HTML gallery |
| `search <pack> <query> [--limit n] [--json]` | ranked search (exit 1 when nothing matches) |
| `list <pack> [--category c] [--unmapped] [--json]` | list icons |
| `stats <pack> [--json]` | counts by category, size and asset-id status |
| `autocomplete <pack> [prefix] [--limit n] [--json]` | names starting with a prefix, for editors and agents |

Every command accepts `--vault <dir>`.

## Not verified

- No real pack has been imported: only the synthetic fixture in `tests/fixtures/visuals-icons/`.
- Upload, moderation and how the icons render in Studio are untested: `NEEDS MANUAL REVIEW`.
- `Visuals.Icons` creates Instances and has not been run in Studio. Its lookup, search and grid maths are covered by Lune specs.
