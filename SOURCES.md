# Sources

Everything the kit learned from, and how each source was used. "Copy" means files may be fetched at a pinned commit with `scripts/install/third_party.py` (never vendored in this repository). "Link" means concepts only: no text or code was copied. Full evaluation: [docs/references/repository-evaluation.md](docs/references/repository-evaluation.md).

## Original work recovered from the user's projects

| Source | Used for |
|---|---|
| Roblox Supermarket 3D asset pipeline (private project, 2026-10 to 2026-11) | `tools/rbxasset/` (meshkit, atlas, safe_area, grid, 61 generators; the 51 approved products as reference specs), the License<N> delivery format, the Blender build, export and verify stages, QA checks, approval-gate workflow, and the modeling skills. Written for the user, so relicensed here under MIT. See [docs/references/recovered-supermarket-pipeline.md](docs/references/recovered-supermarket-pipeline.md). |

## Reviewed third-party repositories

| Repository | License | Pinned commit | Use in the kit |
|---|---|---|---|
| https://github.com/EL4CTEO/blender-skills | MIT | fb92cfb | Copy (optional fetch): 13 Blender skills used in the supermarket project |
| https://github.com/WojciechJelen/roblox-dev-kit | MIT | 5da8287 | Copy (optional fetch): blender-to-roblox, roblox-doctor, find-resources. Its doctor concept inspired `scripts/install/doctor.py` (independently written) |
| https://github.com/gogolumo/rbsmithy-roblox-claude-skill | MIT | bee6014 | Copy (optional fetch): rbsmithy |
| https://github.com/zriptic/roclicks-skills | MIT | a8b66c1 | Copy (optional fetch): roblox-ui-maker, roblox-vfx, roblox-game-score. This is the RoClicks skills repository |
| https://github.com/ahujasid/mcp-for-blender | MIT | 2e4b0bc | Pip install at a pinned commit by `integrations/blender/setup_blender_mcp.sh`; launch scripts adapted from the supermarket project |
| https://github.com/gamedev-skills/awesome-gamedev-agent-skills | Apache-2.0 | 19d93f9 | Link |
| https://github.com/AshExplained/roblox-skills | MIT | a3a7b94 | Link |
| https://github.com/EL4CTEO/roblox-skills | MIT | f94b0e4 | Link |
| https://github.com/SyphoDev-yt/roblox-ai-skills | custom, no resale | 5aad881 | Link: concepts only (license does not allow redistribution) |
| https://github.com/JuliusBrussee/caveman | Apache-2.0 | ca3a524 | Link: optional terse-output skill, not Roblox tooling |
| https://github.com/JoCoding-Inc/roblox-skills | MIT | 9abee35 | Link: new, unreviewed in depth |
| https://github.com/ohzw/roblox-dev-skills | none | 8eb7488 | Link: no license, so nothing reused |
| https://github.com/cream67/gamedev-claude-skills | MIT | c3f2304 | Link: survey only; its installer is not run |
| https://github.com/arjun988/blender-skills | MIT | 904f095 | Link: stylized-look ideas |
| https://github.com/mjclavillas/roblox-3d-design-skills | MIT | f82026a | Link |

## Toolchain (pinned in templates, never vendored)

| Tool | License | Version pinned |
|---|---|---|
| https://github.com/rojo-rbx/rojo | MPL-2.0 | 7.7.1 |
| https://github.com/rojo-rbx/rokit | MIT | 1.2.0 (install manually) |
| https://github.com/UpliftGames/wally | MPL-2.0 | 0.3.2 |
| https://github.com/Kampfkarren/selene | MPL-2.0 | 0.32.0 |
| https://github.com/JohnnyMorganz/StyLua | MPL-2.0 | 2.6.0 |
| https://github.com/JohnnyMorganz/luau-lsp | MIT | 1.70.1 |
| https://github.com/lune-org/lune | MPL-2.0 | 0.11.1 |
| https://github.com/luau-lang/luau | MIT | used in CI for `luau-analyze` |

Recommended libraries (install with Wally, not bundled): ProfileStore (Apache-2.0), roblox-lua-promise (MIT), jecs (MIT), Lyra (MIT), Blink or Zap (MIT), jest-roblox (MIT). Archived and therefore not recommended for new work: TestEZ, Knit, Roblox/studio-rust-mcp-server.

## Documentation

Roblox Creator Documentation (https://github.com/Roblox/creator-docs, CC-BY-4.0) was the reference for API facts. No passages were copied. Where an API detail was uncertain, skills say "verify in creator docs".
