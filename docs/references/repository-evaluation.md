# Repository evaluation

Research done for the kit on 2026-11-08 through the public GitHub API (nothing cloned, nothing installed during research). Stars, dates and SHAs are a snapshot from that day. The decisions this led to are in [`SOURCES.md`](../../SOURCES.md) and [`third_party/manifest.json`](../../third_party/manifest.json).

Method: unauthenticated GitHub REST (`/repos`, `/git/trees`), `git ls-remote HEAD` for SHA, `github.com/<r>/releases/latest` redirect for release tag, raw LICENSE/installer/.mcp.json greps. Nothing cloned or installed. "none" release means no GitHub release. Stars and dates are as of today.

## A. Roblox / AI skill repos

| Repo | License | Stars | Pushed | SHA | Release | Purpose / skills | Roblox use | Security notes | Rec |
|---|---|---|---|---|---|---|---|---|---|
| SyphoDev-yt/roblox-ai-skills | NOASSERTION (custom "free licence": no resale, attribution link required) | 128 | 11-04 | 5aad881 | none | 11 skills: create-roblox-game, roblox-3d-model, roblox-animation, roblox-build-orchestrator, roblox-code, roblox-map, roblox-sfx, roblox-skills-setup, roblox-texture-gen, roblox-ui, roblox-vfx | high | install.sh/.ps1 (no curl pipe in sh), check_setup.py only prints URLs; 3D route uses HF Space (remote) | reimplement concepts (license not OSI; can't copy into a redistributable kit) |
| gogolumo/rbsmithy-roblox-claude-skill | API NOASSERTION, LICENSE file is MIT | 14 | 11-05 | bee6014 | v1.0.2 | 1 mega-skill `rbsmithy` (435 files: systems, templates, prompts) | high | "telemetry" files are game-analytics templates, not tool telemetry | adapt (MIT with project header, so keep attribution); already installed locally |
| WojciechJelen/roblox-dev-kit | MIT | 0 | 10-26 | 5da8287 | none | Claude plugin with 5 skills: blender-to-roblox, find-resources, roblox-doctor, roblox-isolate, roblox-setup | high | install/install.sh, `.mcp.json` runs uvx blender-mcp (network fetch of pinned spec) | reuse (MIT); already installed locally |
| gamedev-skills/awesome-gamedev-agent-skills | Apache-2.0 | 7736 | 10-28 | 19d93f9 | v1.1.0 | 78 multi-engine skills; Roblox ones: roblox-characters, roblox-datastores, roblox-luau, roblox-networking, roblox-physics, roblox-simulator-economy, roblox-studio-workflow, roblox-ui (+ generic game-feel, save-systems, procedural-gen, router) | med | no installers or hooks found | reuse the Roblox subset (Apache, keep NOTICE) |
| JoCoding-Inc/roblox-skills | MIT | 0 | 11-08 | 9abee35 | design-pack-v1.1.0 | 23 skills: roblox-blender-export, -bots-npcs, -character-motion, -cinematics, -combat-tools, -data-saves, -design-and-launch, -dev-workflow, -engine-2026, -feel-audio-vfx, -fun-effects, -game-pipeline, -launch-benchmarks, -market-research, -match-flow, -pitfalls, -project-intake, -release-automation, -store-art-pack, -studio-ai-tools, -ui-genre-studs, -ui-layout, -ui-typography | high | plugin.json only | reuse selectively (pitfalls, ui-*, blender-export); 0 stars and brand new, so review content |
| AshExplained/roblox-skills | MIT | 55 | 07-01 | a3a7b94 | none | 40 skills: roblox-luau-architecture, -datastore-persistence, -creator-store-security-audit, -debugging-bugfix, -performance-optimization, -playtest-qa, -policy-compliance, -monetization-optimization, -economy-balancing, -liveops-roadmap, -release-operations, -security-economy, -ui-implementation, -world-level-design, -to-prd, -to-issues, handoff, write-a-skill, zoom-out, etc. | high (design/ops) | none found | reuse (MIT): security audit, policy, QA, PRD skills |
| ohzw/roblox-dev-skills | none (no LICENSE file) | 27 | 03-02 | 8eb7488 | none | 5 skills: building-3d-objects, building-maps, roblox-build-retrospective, roblox-design-consultant, roblox-ui-mastery | med | `.mcp.json` points at local Roblox Studio MCP app | reimplement concepts only (all rights reserved) |
| cream67/gamedev-claude-skills | API NOASSERTION, LICENSE is MIT | 0 | 10-09 | c3f2304 | none | not a skill repo: survey report + install.py (clones pinned SHAs, runs `claude plugin install`) | low | install.py does subprocess git clone and plugin install | link as reference; don't run |
| zriptic/roclicks-skills (confirmed: the RoClicks repo; sibling zriptic/roclicks-analytics, MIT, 3 stars) | MIT | 14 | 10-15 | a8b66c1 | none | 6 skills: roblox-game-pipeline, roblox-game-score, roblox-trailer, roblox-ui-maker, roblox-vfx, studify, plus a "meshlab" toolkit | med-high | none found | reuse (MIT): game-score, trailer, studify |
| EL4CTEO/roblox-skills (found) | MIT | 91 | 11-03 | f94b0e4 | v1.1.2 | 23 skills: roblox-architecture, -code-review, -data-stores, -networking, -open-cloud, -security, -studio-mcp, -testing, -tooling, -teleport-matchmaking, -text-chat, -npc-ai, -ui, -world-building, etc. | high | scripts/install.sh/.ps1, plugin.json | reuse (MIT); same author as the installed blender-skills |

## B. Blender / 3D

| Repo | License | Stars | Pushed | SHA | Release | Purpose / skills | Roblox use | Security | Rec |
|---|---|---|---|---|---|---|---|---|---|
| arjun988/blender-skills | MIT | 2204 | 11-06 | 904f095 | none | 94 skills, mostly style/genre (cartoon-style, chibi-style, hard-surface, export-pipeline, collision-proxy, asset-optimization, geometry-nodes, ...) | med | `.mcp.json` is Windows-only (`cmd /c uvx blender-mcp`), sets DISABLE_TELEMETRY | adapt the style skills (cartoon/hand-painted) for the stylized look; skip its MCP config |
| ahujasid/blender-mcp, now **ahujasid/mcp-for-blender** (301 redirect) | MIT | 33621 | 11-04 | 2e4b0bc | none | community Blender MCP add-on and server | high | **telemetry.py (httpx), opt-out through DISABLE_TELEMETRY / BLENDER_MCP_DISABLE_TELEMETRY / MCP_DISABLE_TELEMETRY plus a consent check**; install.sh/.ps1; remote asset APIs (Poly Haven, Sketchfab, Hyper3D) | wrap/link; always launch with the telemetry env vars set |
| mjclavillas/roblox-3d-design-skills | MIT | 0 | 10-30 | f82026a | none | 2 skills: roblox-3d-asset-forge, threejs-world-design | low-med | none | reimplement concepts (tiny and unproven) |
| EL4CTEO/blender-skills | MIT | 779 | 11-07 | 389f28a | v1.2.0 | 28 skills: blender-core, -asset-qa, -export-pipelines, -game-optimization, -hardsurface-modeling, -pbr-materials, -retopology-uv, -stylized-npr, -texture-baking, -workflow-recipes, etc. | high | install/install.sh/.ps1; helper bpy scripts | reuse (MIT); already installed locally |

## C. Toolchain

| Repo | License | Stars | Pushed | SHA | Latest release | Purpose | Use | Notes | Rec |
|---|---|---|---|---|---|---|---|---|---|
| rojo-rbx/rojo | MPL-2.0 | 1858 | 10-31 | 84e098e | v7.7.1 | filesystem to Studio sync | high | Studio plugin talks to localhost server | wrap (pin through rokit) |
| UpliftGames/wally | MPL-2.0 | 510 | 10-12 | 009558b | v0.3.2 | package manager | high | registry network calls | wrap |
| rojo-rbx/rokit | MIT | 506 | 09-27 | c8f2799 | v1.2.0 | toolchain manager (aftman successor) | high | README offers a curl pipe to sh installer; prefer brew or a pinned binary | wrap, kit's install entry point |
| Kampfkarren/selene | MPL-2.0 | 839 | 10-01 | 77986eb | 0.32.0 | Lua/Luau linter | high | none | wrap |
| JohnnyMorganz/StyLua | MPL-2.0 | 2334 | 10-30 | d6562ca | v2.6.0 | formatter | high | none | wrap |
| JohnnyMorganz/luau-lsp | MIT | 562 | 11-08 | 2fea186 | 1.70.1 | Luau LSP, type defs | high | fetches API dumps from the network | wrap |
| lune-org/lune | MPL-2.0 | 979 | 10-21 | 0ea4803 | v0.11.1 | standalone Luau runtime (headless tests and scripts) | high | net/process APIs in scripts | wrap |
| Roblox/studio-rust-mcp-server | MIT | 500 | 04-03 | b0b6474 | none (tags reach v0.2.365) | official standalone Studio MCP | high | **archived**; Studio now ships a built-in MCP | link historically; prefer the built-in Studio MCP |
| jsdotlua/jest-lua | MIT | 58 | 2024-12-23 | a5d089a | v3.10.0 | Jest port | med | stale | prefer Roblox/jest-roblox |
| Roblox/jest-roblox (found) | MIT | 50 | 11-06 | 80976df | none | maintained official Jest for Luau | high | none | wrap |
| Roblox/testez | Apache-2.0 | 210 | 2024-03 | 26a5247 | v0.4.2 | BDD tests | low | **archived** | skip, use jest-roblox |
| Sleitnick/Knit | MIT | 630 | 2024-07 | bb1ecf3 | v1.7.0 | game framework | med | **archived** | link only; don't default to it |
| evaera/promise is a 404; the real repo is **evaera/roblox-lua-promise** | MIT | 353 | 2024-08 | 031d429 | v4.0.0 | Promise library | med | stable but quiet | wrap through wally |
| Ukendio/jecs | MIT | 484 | 10-22 | 35e92ec | v0.11.0 | ECS | med | none | wrap (optional) |
| MadStudioRoblox/ProfileStore | Apache-2.0 | 351 | 2025-07 | 45c9847 | none | session-locked DataStore | high | none | wrap, default persistence |
| Data-Oriented-House/lyra is a 404; the real repo is **paradoxum-games/lyra** | MIT | 155 | 03-25 | e8927a9 | v0.6.0 | player data, migrations, transactions | high | none | wrap, alternative to ProfileStore |
| Roblox/creator-docs | CC-BY-4.0 | 895 | 11-07 | ccc2b01 | none | official docs source | high | none | reuse excerpts with CC-BY attribution, use as a RAG source |

## D. Additions found

| Repo | License | Stars | Pushed | SHA | Release | Purpose | Rec |
|---|---|---|---|---|---|---|---|
| seaofvoices/darklua | MIT | 248 | 07-13 | 83a3a9d | v0.19.0 | Luau transforms, bundling, string requires | wrap |
| 1Axen/blink | MIT | 192 | 11-07 | 86b04ef | v0.18.9 | IDL buffer networking codegen | wrap (pick blink or zap) |
| red-blox/zap | MIT | 190 | 06-23 | 8cd17ab | v0.6.29 | networking IDL codegen | wrap |
| Sleitnick/rbxcloud | MIT | 140 | 2025-03 | 251d8c4 | v0.17.0 | Open Cloud CLI/lib (place publish, datastores, messaging) | wrap; publish only with explicit permission |
| boshyxd/robloxstudio-mcp | MIT | 499 | 06-06 | 2e4345d | v2.7.0 | community Studio MCP (more tools than the official one) | link as a fallback; review its plugin first |
| EL4CTEO/roblox-skills | MIT | 91 | 11-03 | f94b0e4 | v1.1.2 | see table A | reuse |

**Avoid / red flags:** search results such as Gddsfik/roblox-universe-deck, FoxyFuck/roblox-cloud-metrics-cli, jlal892/roblox-multiplex-console and suvranshukhilar-alt/rbx-cloud-ops: about 70 stars each, all pushed today, SEO "Best ... 2026" descriptions, no license. This pattern looks like malware or star-farm spam. Claude-Reverser/MCP-Sploit drives an exploit dylib (ToS violation). S4US/Roqer and sebattfg/ZeroScript are AGPL/GPL, so link to them only.

## Top additions found
1. **Roblox/jest-roblox**: the maintained test framework (replaces archived TestEZ and stale jest-lua).
2. **EL4CTEO/roblox-skills** (MIT, 23 skills incl. open-cloud, studio-mcp, testing, security): best-licensed broad Roblox skill set.
3. **paradoxum-games/lyra**: the real "lyra" persistence library (MIT, v0.6.0).
4. **seaofvoices/darklua** and **1Axen/blink** / **red-blox/zap**: bundling and typed networking.
5. **Sleitnick/rbxcloud**: Open Cloud CLI (gate it behind a publish permission).
6. **boshyxd/robloxstudio-mcp**: fallback, since the official standalone Studio MCP repo is archived.

Key corrections: ahujasid/blender-mcp is now ahujasid/mcp-for-blender and has opt-out telemetry. evaera/promise is evaera/roblox-lua-promise. Data-Oriented-House/lyra does not exist (it is paradoxum-games/lyra). Roblox/studio-rust-mcp-server, Roblox/testez and Sleitnick/Knit are archived. SyphoDev and ohzw cannot be copied: SyphoDev has a custom no-resale license and ohzw has no license.
