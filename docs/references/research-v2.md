# Research v2: external resources and gap analysis

Snapshot taken 2026-11-08. It follows [repository-evaluation.md](repository-evaluation.md). The machine-readable list is [`third_party/candidates-v2.json`](../../third_party/candidates-v2.json), which has 66 entries.

**Method.** I read licenses from each repo's raw `LICENSE` file. "Last push" is the newest commit on the default branch, from `commits.atom` or GitHub API `pushed_at`. Release tags come from the `releases/latest` redirect. **Wally names and versions were checked against the public registry API** (`api.wally.run/v1/package-metadata/<scope>/<name>`) and against each repo's `wally.toml`. Nothing was cloned, installed or run. "Verified" in the JSON means the registry returned the package, or for tools, that the release tag resolved.

Registry and repo disagree in several places. In each case, pin what the registry has:

- **Lyra:** the repo says 0.6.1, the registry has 0.6.0.
- **Fusion:** the repo is 0.4.0-dev1, the registry has 0.3.0.
- **Conch:** the repo's `wally.toml` still says `alo/conch@0.1.0`, the registry has `alicesaidhi/conch@0.4.0`.
- **ByteNet:** the repo says `ffrostfall/bytenet@0.5.0`, the registry has `ffrostflame/bytenet@0.4.6`.
- **ZonePlus:** the repo declares `1foreverhd/zoneplus`, but it is not on the registry.

## 1. Candidates by category

Integration options: **wally** (add as a dependency), **tool** (pin with Rokit), **adapter** (the kit wraps or processes it), **reimplement** (borrow concepts, write our own), **link** (document only), **skip**.

### Runtime libraries (Wally)

| Package | License | Last push | Wally (verified) | Rec | Why |
|---|---|---|---|---|---|
| ProfileStore | Apache-2.0 | 2025-07 | `lm-loleris/profilestore@1.0.3` | **wally, default** | Session-locked saves. Today the templates only mention it in a comment. |
| Lyra | MIT | 2026-03 | `paradoxum-games/lyra@0.6.0` | wally, alternative | Migrations, transactions, large records |
| DocumentService | MIT | 2026-09 | `anthony0br/documentservice@1.2.2` | link | Third option; avoid three defaults |
| Charm + charm-sync | MIT | 2026-10 | `littensy/charm@0.11.1`, `littensy/charm-sync@0.4.1` | **wally, optional** | Best-maintained state plus server-to-client sync |
| Replica | Apache-2.0 | 2025-08 | not on registry | reimplement | Subscribe a player to a state: a pattern our Systems need |
| RbxUtil | MIT | 2026-07 | `sleitnick/component@2.4.8`, `input@3.0.0`, `streamable@1.2.4`, `signal@2.0.3`, `trove@1.8.0`, `comm@1.0.1`, `timer@2.0.0`, `log@0.1.2`, `buffer-util@0.3.2`, `table-util@1.2.1` | wally (component, input, streamable) | Proven building blocks we do not have |
| Promise | MIT | 2024-08 | `evaera/promise@4.0.0` | wally, optional | Stable |
| t | MIT | 2025-03 | `osyrisrblx/t@3.1.1` | reimplement | `Util/Validate` already covers it and adds range and size limits |
| Janitor | MIT | 2025-10 | `howmanysmall/janitor@1.18.3` | link | Overlaps Trove |
| jecs | MIT | 2026-10 | `ukendio/jecs@0.11.0` | wally, optional | ECS for large simulations |
| Iris | MIT | 2026-10 | `sirmallard/iris@2.5.1` | **wally (dev)** | Debug panels |
| Cmdr | MIT | 2026-10 | `evaera/cmdr@1.13.1` | **wally, optional** | Admin and debug console with permission hooks |
| Conch | MIT | 2026-11 | `alicesaidhi/conch@0.4.0` | link | Newer console, also on pesde |
| ripple | MIT | 2026-03 | `littensy/ripple@0.10.2` | wally, optional | UI springs; replaces Flipper (2021, dead) |
| spr | MIT | 2024-07 | not on registry | reimplement | Small damped spring for UrkUI |
| ui-labs utility | MIT (plugin is GPL-3.0) | 2026-08 | `pepeeltoro41/ui-labs@2.4.2` | **wally (dev)** | Story files for UrkUI components |
| TopbarPlus | custom, credit required | 2026-10 | `1foreverhd/topbarplus@3.5.0` | link | Not OSI; never bundle |
| ZonePlus | MIT | 2024-07 | not on registry | reimplement | Small Zone system |
| React (jsdotlua) | MIT | 2025-05 | `jsdotlua/react@17.2.1`, `jsdotlua/react-roblox@17.2.1` | link | Large-team UI option |
| Fusion / Vide | MIT | 2026-02 / 2026-10 | `elttob/fusion@0.3.0`, `centau/vide@0.4.1` | link | Use Vide's model if UrkUI adds reactivity |
| LemonSignal, Squash, Sift | MIT | 2026-07 / 2026-01 / 2025-03 | `data-oriented-house/lemonsignal@2.0.0`, `data-oriented-house/squash@5.0.0`, `csqrl/sift@0.0.11` | link | Niche utilities |
| ByteNet | MIT | 2025-08 | `ffrostflame/bytenet@0.4.6` | skip | Blink preferred |
| GameAnalytics SDK | MIT | 2026-10 | `gameanalytics/gameanalytics-sdk@3.0.0` | link | Optional; build on AnalyticsService first |
| jest-roblox | MIT | 2026-11 | `roblox/jest@3.20.1`, `roblox/jest-globals@3.20.1` | **wally (dev)** | The maintained Jest |
| NevermoreEngine | MIT | 2026-11 | npm only (Wally has canaries only) | reimplement | ServiceBag, Binder, Brio concepts |
| Knit, ReplicaService, jest-lua, Flipper, Hoarcekat | n/a | old | n/a | skip | Archived, stale or superseded |

Packet (Suphi) is distributed through the DevForum and the Creator Store, with no Git repo to pin, so it is skipped.

### Tools (Rokit)

| Tool | License | Last push | Pin | Rec | Use |
|---|---|---|---|---|---|
| Asphalt | MIT | 2026-07 | `jacktabscode/asphalt@2.0.2` | **tool** | Uploads images, audio and models through Open Cloud, generates a Luau asset-id module, uses a lockfile and can pack atlases |
| rocale-cli (Roblox) | MIT | 2026-05 | `Roblox/rocale-cli@0.1.3` (tag verified; its README documents Foreman, so the Rokit pin is unverified) | **tool** | Build, upload and run Luau through Open Cloud Luau Execution, which gives in-engine tests in CI |
| Mantle | MIT | 2026-05 | `blake-mealey/mantle@0.11.18` | **tool** | Infrastructure as code: places, staging and prod environments, passes, products, badges, thumbnails |
| rbxcloud | MIT | 2025-03 | `Sleitnick/rbxcloud@0.17.0` | tool | Place publish, DataStore and MessagingService from the CLI |
| Blink | MIT | 2026-09 | `1Axen/blink@0.18.9` | **tool** | The kit's one networking IDL |
| Zap | MIT | 2026-06 | `red-blox/zap@0.6.29` | link | Equivalent; keep a single default |
| darklua | MIT | 2026-07 | `seaofvoices/darklua@0.19.0` | tool | Bundle `library/` as `.rbxm`, rewrite requires, inject `__DEV__` |
| luau-lsp, Lune, selene, StyLua, Rojo, Wally | MIT / MPL-2.0 | current | already pinned, all at latest | keep | Also run `luau-lsp analyze` in CI |
| moonwave | MPL-2.0 | 2026-06 | npm `moonwave@1.4.2` | tool (Node, optional) | API docs site from `--[=[ ]=]` comments |
| Argon | Apache-2.0 | 2026-05 | `argon-rbx/argon@2.0.29` | link | Rojo alternative with two-way sync |
| pesde | MIT | 2026-10 | `pesde-pkg/pesde@0.7.4+registry.0.2.3` | link (watch) | Newer package manager |
| Foreman | MIT | 2026-05 | n/a | link | Doctor should recognize `foreman.toml` |
| Tarmac, Aftman, run-in-roblox, roblox-ts | MIT | stale or archived | n/a | skip | Superseded, or out of scope (roblox-ts v3.0.0) |
| place-ci-cd-demo | MIT | 2024-09, archived | n/a | reimplement | Its concurrency-group pattern (Luau Execution allows 2 concurrent tasks per universe) |

### MCP, Blender and icons

| Resource | License | Rec | Notes |
|---|---|---|---|
| Studio built-in MCP | Roblox terms | **adapter** | 26 tools, including `execute_luau`, `start_stop_play`, `get_console_output`, `screen_capture`, `character_navigation`, `insert_asset`, `generate_mesh` and `list_roblox_studios`. Our config only has the macOS command; Windows is `cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`. |
| boshyxd/robloxstudio-mcp v2.7.0, EL4CTEO/rbx-studio-mcp v1.0.6 | MIT | link | Community fallbacks; review their plugins first. EL4CTEO's is new, with 14 stars. |
| Roblox Blender Plugin v1.0.5 | MIT | link | Official upload from Blender; the user signs in with OAuth |
| Lucide 1.70.0 | ISC | **adapter, default** | Clean UI glyphs |
| Phosphor core 2.0.8 | MIT | **adapter** | Bold and fill weights suit the chunky style |
| Tabler 3.50.0 | MIT | adapter | Over 5000 icons |
| Kenney Game Icons | CC0 | **adapter** | Game glyphs; no attribution needed |
| Material Symbols | Apache-2.0 | link | Keep the NOTICE file |
| game-icons.net | CC-BY-3.0 | link, opt-in | Per-author credit needed in game; keep out of the default atlas |

## 2. Gap analysis

Compared against Nevermore, Knit-era stacks (Knit, Promise, Component, Comm, ProfileService), RbxUtil-based stacks and typical studio pipelines (Rojo, Wally, Asphalt, Mantle, Jest in CI).

### Missing capabilities

1. **No real dependency use.** Template `wally.toml` files have no live dependencies, and no project maps a `Packages` folder. The kit recommends libraries but never exercises them.
2. **No asset sync.** The Blender pipeline ends at FBX, OBJ and GLB on disk. Nothing turns outputs or icons into asset IDs in code. Asphalt is the standard answer. The kit's fetched `blender-to-roblox` skill uploads ad hoc, which duplicates that job.
3. **No deploy or environment model.** There is no staging or prod split, no versioned place publish, and no declared monetization config (passes and products as code). Mantle covers this; rbxcloud is the lighter option.
4. **No in-engine tests.** Lune covers pure Logic only. The Server and Client adapters, which use remotes, DataStores and CollectionService, are never run.
5. **No place build in CI.** CI never runs `rojo build`, so a broken `default.project.json` or an instance-path require only fails in Studio.
6. **No state replication, zones, input, admin console or debug UI.** The library's Systems need a replication primitive: Replica-style or Charm-sync.
7. **No analytics.** There is no wrapper over `AnalyticsService` for economy, funnel and progression events, which the monetization and liveops skills assume.
8. **No API docs generation.** Library READMEs are hand-written. Moonwave would keep the API tables in sync with the code.

### Weak or outdated implementations

| Item | Problem | Fix |
|---|---|---|
| `roblox-testing-debugging` skill | Calls jsdotlua Jest-Lua "actively maintained" (last push 2024-12). Recommends TestEZ (archived) and run-in-roblox (stale since 2024). | Switch to `roblox/jest@3.20.1` plus rocale-cli or Luau Execution |
| `PlayerDataService` (289 lines, custom session lock) | Competes with ProfileStore, and a hand-rolled lock is the riskiest code in the kit | Ship a `ProfileStore` adapter as the default and keep this file labelled "reference" |
| Signal and Trove | Copied into `starter-game/src/shared` and `library/src/Util`, and composed into every template | One source (`library/Util`) composed by `new_project.py`; test for drift |
| `tests/lib/t.luau` | Its name collides with the well-known `osyrisrblx/t` runtime checker | Rename to `tests/lib/expect.luau` or `spec.luau` |
| Luau analysis in CI | `luau-analyze --mode=strict` runs only on `Logic/*.luau`, with no Roblox type definitions | `rojo sourcemap` then `luau-lsp analyze --definitions=... --sourcemap=...` over all of `src` |
| Studio MCP | macOS-only config. The `roblox-studio-mcp` skill tool list predates the 26-tool server. | Add a Windows entry and refresh the tool table from the Creator Hub page |
| Third-party pins | blender-skills is pinned at fb92cfb while upstream is v1.2.0 (389f28a). awesome-gamedev and ashexplained use short SHAs. | Re-review, then pin full SHAs |

### Security

- **CI downloads binaries with `curl | unzip`** for selene, stylua, lune and luau, with no checksum check. Use Rokit in CI, or pin SHA256 values next to the URLs.
- **Open Cloud keys.** Asphalt, Mantle, rocale-cli and rbxcloud all need keys. Set a policy: environment variables or the CI secret store only, never in files. Give each tool its own key with the fewest scopes, and restrict keys by IP where possible. Keep the publish and deploy scripts behind an explicit `--confirm-publish` flag plus a human approval, which matches the kit's existing rules.
- **Wally supply chain.** Pin exact versions, commit `wally.lock`, and add a validator that rejects `^` and `*` ranges in templates.
- **Admin consoles.** Cmdr and Iris must default to off in production builds. Gate Cmdr with server-side permission hooks keyed on group rank or userId, never a client check.
- **Free models.** The backdoor scan in `find-resources` is a fetched skill. A small built-in `scan_rbxm.py` written with Lune would reduce that dependency.

### DX and docs gaps

- No `.vscode/` recommendations (luau-lsp, selene and stylua extensions, sourcemap autogeneration) and no `rojo sourcemap --watch` guidance.
- No "choosing a stack" page: Knit-era versus modern (Charm, Blink, jecs, Vide or React).
- No release or deploy guide, no environments doc, and no Open Cloud key setup guide.
- Doctor does not detect `foreman.toml`, `aftman.toml`, `wally.lock` drift or a missing `Packages` folder.
- No icon pipeline doc. `library/src/Icons` is empty and has no license manifest.

## 3. Roadmap

Effort: S is under 1 day, M is 1 to 3 days, L is about a week.

### P0: correctness and safety

| # | Item | Effort | Implementation notes |
|---|---|---|---|
| 1 | Fix the testing skill and docs | S | Replace Jest-Lua, TestEZ and run-in-roblox with `roblox/jest@3.20.1` and `roblox/jest-globals@3.20.1` as Wally dev-dependencies, and rocale-cli or Luau Execution for CI. Keep Lune for Logic. |
| 2 | Real Wally deps in `starter-game` | M | Add `ProfileStore = "lm-loleris/profilestore@1.0.3"`, map `Packages` and `ServerPackages` in `default.project.json`, commit `wally.lock`, and write a `ProfileStoreAdapter` that fits the library's injected `store` interface. Add a validator that rejects range versions. |
| 3 | Place build in CI | S | In the luau job, run `wally install && rojo build -o build/<t>.rbxl` per template, then `rojo sourcemap` and `luau-lsp analyze` across all of `src` with the Roblox definitions file pinned to a version. |
| 4 | Checksum-pinned CI tools | S | Move to `rokit install` using each template's `rokit.toml`, or add `sha256sum -c` lines. Pin `actions/*` by SHA. |
| 5 | Remove Signal and Trove duplication | S | `new_project.py` composes from `library/src/Util`. Add a test that fails if template copies drift. Rename `tests/lib/t.luau`. |

### P1: high-value automation and systems

| # | Item | Effort | Implementation notes |
|---|---|---|---|
| 6 | Asphalt asset sync | M | Add `asphalt@2.0.2` to Rokit, and `templates/asset-pipeline/asphalt.toml` mapping `build/<batch>/*.png` and the icons to `src/shared/Assets.luau`. Commit the lockfile. The upload step needs an explicit permission flag and an env key. Hook it after `package_batch.py`. |
| 7 | Icon pipeline | M | `scripts/export/build_icons.py` downloads pinned releases (Lucide, Phosphor, Kenney, optionally Tabler), rasterizes SVGs to 64 and 128 px PNGs, packs atlases, and writes `library/src/Icons/catalog.luau` with per-icon license and source plus a `LICENSES/` folder. CC-BY sets are opt-in and add generated credits. Asphalt uploads the result. |
| 8 | Opt-in in-engine CI | M | `.github/workflows/engine-tests.yml`, triggered by `workflow_dispatch` or when the `ROBLOX_API_KEY` secret exists. It runs rocale-cli against a dedicated test place, with concurrency group `luau-exec-${universe}` capped at 2. The entry script runs Jest and returns JSON results. Report "skipped (no key)" otherwise. |
| 9 | Release and deploy workflow | M | `templates/*/mantle.yml` with `staging` and `production` environments, passes, products and badges as code. Add a `release` workflow step: `mantle deploy --environment staging` only, while production requires the user's chat approval. Use rbxcloud as the no-state fallback. Update the `roblox-publishing-liveops` skill. |
| 10 | Library Systems: Replication, Zone, Analytics | L | `Systems/Replication`: a Replica-style per-player state with path set and listen, or an adapter to Charm-sync. `Systems/Zone`: a spatial-query polling zone with enter and leave signals. `Systems/Analytics`: a wrapper over `AnalyticsService` with economy, funnel, progression and custom events, plus pure Logic for funnel step ordering. Pure Logic gets Lune specs. |
| 11 | Studio MCP refresh | S | Add a Windows `mcp.bat` entry and a 26-tool table in `roblox-studio-mcp`. Doctor checks the "Enable Studio as MCP server" state by trying `list_roblox_studios`. |
| 12 | Dev tools overlay | M | `templates/devtools` overlay: Iris debug panel and Cmdr with server permission hook (dev-only, stripped by a `__DEV__` flag via darklua or a Config flag), and UI Labs stories for UrkUI components. |
| 13 | Blink networking overlay | M | `templates/networking-blink`: `net.blink` schema, `blink@0.18.9` in Rokit, and generated modules gitignored and built in CI. Keep `Net.luau` for small games, and document when to switch. |

### P2: polish and reach

| # | Item | Effort | Implementation notes |
|---|---|---|---|
| 14 | Moonwave API docs | M | Add `--[=[ @class ]=]` comments to the library, a `moonwave.toml`, and a GitHub Pages workflow (Node only in that job). |
| 15 | darklua bundle of `library/` | S | Release `UltimateRobloxKit.rbxm` with requires rewritten. Attach it to a GitHub release. |
| 16 | "Choosing a stack" and Open Cloud keys docs | S | Cover Knit-era versus modern stacks (Charm, Blink, jecs, Vide or React). Give a per-tool key scope table and IP restriction steps. |
| 17 | Doctor upgrades | S | Detect foreman and aftman manifests, `wally.lock` drift, a missing `Packages` folder, and stale Rokit pins against latest releases (read-only check). |
| 18 | Built-in rbxm backdoor scanner | M | A Lune script that flags `require(<number>)`, `getfenv`, `loadstring`, obfuscated strings and `HttpService` in inserted models. |
| 19 | Watch list | S | pesde, Vide reactivity for UrkUI, EL4CTEO/rbx-studio-mcp, Lyra 0.6.1 publication. Re-run this research quarterly. |
| 20 | Nevermore concepts | M | Add a Binder (tag to class lifecycle) and a ServiceBag-style dependency-injection option in `roblox-architecture`, as reimplementations. |

## Sources

- Creator Hub, [Studio MCP server](https://create.roblox.com/docs/studio/mcp) and [Luau Execution](https://create.roblox.com/docs/cloud/reference/features/luau-execution.md)
- DevForum, [Open Cloud Engine API for Executing Luau](https://devforum.roblox.com/t/beta-open-cloud-engine-api-for-executing-luau/3172185)
- [Roblox/rocale-cli](https://github.com/Roblox/rocale-cli) and [Roblox/place-ci-cd-demo](https://github.com/Roblox/place-ci-cd-demo)
- The Wally registry API, and each repository linked in `candidates-v2.json`
