# Asset pipeline project template

A folder layout for producing Roblox assets with the kit, following the batch workflow from the supermarket project.

```
specs/            one JSON spec per batch (about five assets each, similar shapes)
build/<batch>/    generated outputs, rebuildable, git-ignored
dist/<batch>/     approved deliverables from package_batch.py
CREDITS.md        every external asset or font, with its license
```

## Use

Copy this folder into your asset repository (or a game repo's `assets/` folder), then:

```bash
python3 .claude/ultimate-roblox-kit/scripts/export/asset_batch.py specs/batch-01.json --out build/batch-01
```

```bash
python3 .claude/ultimate-roblox-kit/scripts/export/asset_batch.py --approve Crate build/batch-01
```

```bash
python3 .claude/ultimate-roblox-kit/scripts/export/package_batch.py build/batch-01 --dest dist/batch-01 --zip dist/batch-01.zip
```

Inside the kit repository itself, drop the `.claude/ultimate-roblox-kit/` prefix. Approve only what the person who owns the art has approved. See the `batch-asset-production` skill.
