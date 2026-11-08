---
name: asset-sourcing-licensing
description: Finding and safely using external assets and code - Creator Store models, CC0 sources (Poly Haven, ambientCG, Kenney), fonts, sounds, GitHub libraries - with license checks (CC0 and MIT preferred, CC-BY credited, no non-commercial or unknown), backdoor scans of free models, credits files, and when to build instead. Use when the user wants a free model, texture, sound, font or library, or asks whether something is safe or allowed to use.
license: MIT
metadata:
  category: modeling
  version: 1.0.0
  triggers: [free model, creator store, toolbox, cc0, license, credits, kenney, poly haven, backdoor]
  depends: [roblox-security-anti-exploit]
---

# Asset sourcing and licensing

## Decide: find or build

Build with the kit when the shape is a container, box, furniture, wall or simple prop (fast, consistent, original). Find when it is organic and laborious (trees in bulk, animals, realistic rocks, sound effects, music).

## License rules

| License | Use |
|---|---|
| CC0, public domain | yes, credit optional |
| MIT, Apache-2.0, BSD, MPL-2.0 | yes, keep the license text; MPL file changes stay MPL |
| CC-BY | yes, with credit in `CREDITS.md` |
| SIL OFL (fonts) | yes, keep the OFL text beside the font |
| CC-BY-SA, GPL, AGPL | avoid in shipped game content or code unless the user accepts share-alike |
| NC, ND, "personal use", no license | no |

Record every external item in `CREDITS.md`: name, source URL, author, license, date, what it is used for.

## Free model safety (Creator Store)

Before using any model with scripts, save it as `.rbxmx` and run `python3 $URK/scripts/security/scan_models.py Model.rbxmx` (or `lune run $URK/scripts/security/scan_models.luau Model.rbxm`); it exits 1 on high-risk findings. Manually, search its descendants for `require(` with a number, `getfenv`, `setfenv`, `loadstring`, `HttpService`, `MarketplaceService:PromptPurchase`, `TeleportService`, obfuscated strings and `Script` objects hidden in odd places. Delete scripts you do not need. Prefer script-free meshes.

## Code libraries

Install through Wally with a pinned version; read the source before adding; note the license. Recommended, reviewed 2026-11-08: ProfileStore (Apache-2.0), roblox-lua-promise (MIT), jecs (MIT), Lyra (MIT), Blink or Zap (MIT).

## Limitations

License data comes from the source page and can be wrong; when in doubt, ask the author or skip it. The kit does not download assets automatically.
