# Contributing

## Setup

```bash
python3 scripts/validate/run_all.py
```

No packages are needed. Blender (optional) enables the end-to-end asset test, and Pillow (optional) enables contact sheets.

## Adding a skill

1. Before writing anything, check that no existing skill covers it: `python3 scripts/automation/route.py "<the task>"`. Prefer extending a skill over adding a near-duplicate.
2. Create `skills/<category>/<name>/SKILL.md` following [the skill format](docs/architecture/skill-format.md). Keep the body under about 250 lines and move detail into `references/`.
3. Give it distinctive triggers, and declare `depends` only for skills that must be read alongside it.
4. Run `python3 scripts/automation/build_catalog.py`, add a routing case to `tests/routing_cases.json`, and run `python3 scripts/validate/run_all.py`.

## Adding a generator

Add a function `name(w, d, h, **params) -> MeshData` in `tools/rbxasset/generators/` and register it in `GENERATORS`. `tests/test_rbxasset.py` automatically checks it for closed, outward geometry at two sizes. Build it once with `scripts/export/asset_batch.py` and look at the renders.

## Third-party material

Open an issue first. Record the license, a full pinned commit, the security review and the reuse policy (`copy`, `link`, `pip`) in `third_party/manifest.json` and `SOURCES.md`. Only MIT, Apache-2.0, BSD, MPL-2.0 or CC0 material can use `copy`.

## Pull requests

Use a feature branch, write meaningful commits, and fill in the PR checklist. CI must pass. State what you could not verify, such as Studio behaviour.
