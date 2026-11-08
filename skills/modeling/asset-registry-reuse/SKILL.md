---
name: asset-registry-reuse
description: Reuse before you make - index every image, mesh, audio file, font, Luau module and spec in the kit or a project with the asset registry, search by name and tags, get reuse suggestions for a request, and find identical files and near-duplicate images (shape hash plus average colour), with the licence found beside each asset. Use before generating or downloading any new asset, when cleaning up an asset library, or when asked whether an asset already exists or is a duplicate.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [asset registry, reuse an asset, duplicate assets, near duplicate, find an existing asset, asset library, do we already have, asset search]
  depends: [asset-sourcing-licensing]
---

# Asset registry and reuse

## Workflow

1. **Index**: `python3 $URK/urk.py assets scan` (kit assets and examples), or pass project folders: `python3 $URK/urk.py assets scan ~/games/MyGame/assets`. Writes `.urk/assets.json`.
2. **Before making anything**, ask the registry: `python3 $URK/urk.py assets suggest "gold coin icon"`. Reuse a hit when its licence fits; say which file you reused.
3. **Search** by words and kind: `python3 $URK/urk.py assets search crate --kind mesh`.
4. **Duplicates**: `python3 $URK/urk.py assets dupes` lists identical files (same sha256) and near-duplicate images (hash distance up to `--near`, default 2, and similar average colour). Keep one, update references, delete the rest only with the user's OK.
5. **Licences**: every media file should show a licence. "no licence found" means record the source (`asset-sourcing-licensing`) or remove it. `python3 $URK/urk.py audit --project <dir>` flags these too.

## Limitations

- Tags come from paths and file names, so well-named files are found and `IMG_0042.png` is not.
- Near-duplicate detection is for images only. Meshes are compared by exact bytes.
