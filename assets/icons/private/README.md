# Private icon packs

This folder is the icon vault. Everything in it except this README is git-ignored, because paid icon packs usually may not be redistributed.

- `tools/icons/vault.py import` copies a pack here byte-for-byte: `<pack>/original/` holds the untouched files (read-only), `<pack>/manifest.json` and `<pack>/SHA256SUMS` record their SHA-256 hashes.
- Registries, asset-id maps, the generated Luau data module, derived images, sprite sheets and the HTML preview are written beside the originals, never over them.
- Do not edit, rename, recompress or delete anything under `original/`. `python3 tools/icons/vault.py verify <pack>` proves nothing changed.
- Do not force-add these files to git unless the pack's licence explicitly permits redistribution.

Status: the paid pack has not been supplied yet, so the import is pending. `python3 tools/icons/vault.py status` reports the current state. The full procedure is in [docs/workflows/icon-pack-import.md](../../../docs/workflows/icon-pack-import.md).
