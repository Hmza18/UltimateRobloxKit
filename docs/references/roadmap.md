# Roadmap

Prioritized from the V2 gap analysis ([research-v2.md](research-v2.md)) and the original blueprint. Status reflects 0.4.0 (branch `feat/ecosystem-v4`). P0 covers correctness and safety, P1 high-value automation and systems, P2 polish. Effort: S is under a day, M is 1-3 days, L is about a week.

## Done in V2

| # | Item | Where |
|---|---|---|
| P0-1 | Testing skill points at maintained tools: Roblox Jest 3.20.1 and rocale-cli, with TestEZ and run-in-roblox marked stale | `skills/roblox/roblox-testing-debugging` |
| P0-3 | Every template and the library are built into place and model files by Rojo in CI. A whole-library luau-lsp type check runs as a report | `.github/workflows/ci.yml` |
| P0-4 | CI binaries verified by SHA-256 from GitHub's release digests, Blender by its published checksum, and actions pinned by commit | `.github/workflows/ci.yml` |
| P0-5 | Shared utilities (Signal, Trove, RateLimiter, Validate) guarded by a sync test, so the template and library copies cannot drift | `tests/test_urk_cli.py` |
| P1-7 | Icon library: 92 original MIT icons, sprite sheets, catalog, Luau API, gallery, and an importer for packs you download yourself | `assets/icons/`, `tools/icons/`, `library/src/Icons/` |
| P1-10 | Library systems, including Analytics, Zones and Binder | `library/src/Systems/` |
| P1-11 | Studio MCP config from the official docs for macOS and Windows, a tool table, and doctor detection | `integrations/mcp/`, `roblox-studio-mcp` |
| P2-18 | Backdoor scanner for scripts and models: Python for text formats, Lune for binary, tested on fixtures | `scripts/security/` |
| New | UrkUI tag-based UI framework | `library/src/UI/` |
| New | `urk.py`: setup, new, add, check, upgrade, uninstall, icons, dashboard | `urk.py` |
| New | Local developer dashboard | `scripts/dashboard/` |
| New | `add_module.py`: copies library modules into a project with dependencies, protects your edits, and supports remove | `scripts/automation/add_module.py` |
| New | Skills for project planning, Luau debugging, gameplay testing, maintenance, UI framework, icons and the component library. Agents for UI, testing and performance, plus cooperation rules | `skills/`, `.claude/agents/`, `docs/architecture/agent-cooperation.md` |

## Done in V4 (0.4.0)

Audit on 2026-11-08 found these as the highest-impact gaps: no simulator progression systems (pets, rebirths, trading), no licensed art beyond the kit's own icons, persistence without the community standard, no way to measure UI against a reference, no whole-game generation, no economy tooling, and routing never measured on unseen tasks.

| # | Item | Where |
|---|---|---|
| P0-2 | Wally overlay: `urk packages` writes pinned Fusion, Promise and ProfileStore (server realm), maps Packages, runs `wally install`. `ProfileStoreAdapter` and `FusionBridge` integrate them | `scripts/automation/packages.py`, `library/src/Integrations/` |
| V4-1 | Systems: Pets (eggs, rarity, pity, luck, fuse), Rebirth, Upgrades, Worlds, Boosts, Trading (versioned offers, atomic swap), Progression server, VFX tiers, WorldGen | `library/src/Systems/` |
| V4-2 | CC0 art: Kenney Game Icons (+expansion, coloured set) and UI Pack 2.0, with provenance and hashes | `assets/icons/kenney-*`, `assets/ui/` |
| V4-3 | Visual UI loop: reference extraction and a scored comparison rubric, skill and agent | `tools/ui/visual.py`, `roblox-visual-ui-loop`, `urk-visual-ui` |
| V4-4 | Game generator for six genres, verified to build and pass Lune, Selene, StyLua and Rojo | `scripts/automation/generate_game.py` |
| V4-5 | Economy simulator, asset registry, LOD and collision hulls, audit, build, memory and release gate | `tools/`, `scripts/` |
| V4-6 | Routing evaluation with two held-out sets; description fallback in the router | `catalog/route_eval.json`, `scripts/automation/skills.py` |
| V4-7 | Dashboard: Project, UI Playground, Assets, Agents and Tests centres | `scripts/dashboard/` |

## Done in 0.5.0

UltimateVisualsKit: the visual layer (`library/src/Visuals/`), 17 animated game components, ten themes, generated VFX textures, a private icon vault, a generated preset catalog (`catalog/visuals.json`), 15 `uvk-*` skills, two agents and two commands. Status, what was verified and what remains (first of all a Studio pass, since nothing in it has been run in Roblox) are in [PROGRESS.md](../../PROGRESS.md) and [the status section of the architecture document](../architecture/visuals.md#status-and-deviations).

## Next (recommended order)

| # | Item | Effort | Notes |
|---|---|---|---|
| R-1 | Routing on unseen tasks: held-out accuracy is 40-50% while tuned cases are 100%. Grow the evaluation from real requests and try better generalisation (synonym lists per skill, or let Claude's own skill matching decide and treat the router as a hint) | M | Never tune against `heldout2`; add a new held-out set after each change |
| R-2 | Studio validation of the new server adapters (PetsServer, ProgressionServer, TradingServer) and WorldGenBuilder in a test place | M | Needs Studio; record results in `validation-status.md` |
| R-3 | Studio capture in the visual loop through the Roblox Studio MCP | S | The path is documented; it needs a connected Studio to verify |


| # | Item | Effort | Notes |
|---|---|---|---|
| P0-2b | Jest dev dependencies through the same Wally overlay, and a committed `wally.lock` in templates | S | The overlay exists; Jest needs the in-engine runner (P1-8) to be useful |
| P1-8 | Opt-in in-engine CI through rocale-cli against a dedicated test place | M | Only runs when `ROBLOX_API_KEY` is set, and reports "skipped" otherwise. Needs a key from you |
| P1-6 | Asphalt asset sync (`jacktabscode/asphalt@2.0.2`) after `package_batch.py` and for icon sheets | M | Uploads need explicit permission each time. Verify its config schema before adding a template |
| P1-9 | Mantle release flow (`blake-mealey/mantle@0.11.18`): staging deploys automatically, production waits for approval | M | Needs a test experience |
| P1-12 | Dev-tools overlay (Iris, Cmdr, UI Labs stories for UrkUI) | M | UI Labs' plugin is GPL-3.0, but its utility package is MIT: link the plugin, depend only on the package |
| P1-13 | Blink networking overlay (`1Axen/blink@0.18.9`) | M | Keep `Net` for small games |
| P2-14 | Moonwave API docs for the library | M | Node.js only in that CI job |
| P2-15 | darklua-bundled `UltimateRobloxKit.rbxm` attached to GitHub releases | S | CI already builds the `.rbxm` artifact |
| P2-17 | Doctor: detect stale pins against the latest releases, `wally.lock` drift and Foreman or Aftman manifests | S | |
| P2-20 | Nevermore-style ServiceBag dependency injection as an architecture option | M | Binder is done |
| UI-next | Clear the 153 luau-lsp findings (mostly adapters), make the full type check blocking, and add Studio playtest checklists per UrkUI component | M | The blocking luau-analyze check on all 48 pure modules already passes |

## Not planned

Knit, Aftman, Tarmac, Roact (archived, Apache-2.0), run-in-roblox and studio-rust-mcp-server are archived or stale. roblox-ts is a different toolchain. Copying TopbarPlus (custom licence) or the General UI Kit (paid, closed source) is also ruled out: UrkUI is an independent implementation of similar ideas.
