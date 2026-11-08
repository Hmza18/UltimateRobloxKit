---
description: Build, export and QA a batch of procedural Roblox assets, then stop for approval
argument-hint: <spec.json or description of the assets>
---
Read the `batch-asset-production` skill. If $ARGUMENTS is a spec file, use it; otherwise write a spec of at most five assets from the description, choosing generators listed in `procedural-mesh-generation`. Run `python3 .claude/ultimate-roblox-kit/scripts/export/asset_batch.py <spec> --out build/<batch>`. Fix FAILs at their cause, up to three rounds each. Open the contact sheet and the views, describe what you see, and show them to the user. Stop and wait for approval. Do not approve anything yourself.
