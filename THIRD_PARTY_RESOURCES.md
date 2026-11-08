# Third-party resources

Everything from outside the kit, why it is here, under which licence, and how it arrives. Changing a name never removes a licence obligation: the original author and licence stay attached to every file listed here. Checked on 2026-11-08.

## Bundled in this repository (redistribution allowed)

| Resource | Author | Licence | Where | What changed |
|---|---|---|---|---|
| Game Icons and Game Icons Expansion (white glyphs, 186) | Kenney Vleugels (kenney.nl) | CC0 1.0 | `assets/icons/kenney-game/` (sheets, `icons.json`, `PROVENANCE.md` with per-file hashes, `LICENSE-kenney.txt`) | Trimmed, centred in 128 px cells, packed into 3 sheets by `tools/icons/import_pack.py`. Artwork unchanged. Names prefixed `kenney-` |
| Game Icons Expansion, coloured set (17) | Kenney Vleugels | CC0 1.0 | `assets/icons/kenney-color/` | Same packing; names `kenney-<name>-color`, so `IconCatalog.styled(name, "color")` finds them |
| UI Pack 2.0 (buttons, panels, sliders, checkboxes in 5 colours plus extras, 6 UI sounds, Kenney Future fonts) | Kenney Vleugels | CC0 1.0 | `assets/ui/kenney-ui-pack/` | Copied as is (the "Default" size set) |
| Lilita One, Fredoka | Juan Montoreano; The Fredoka Project Authors | SIL OFL 1.1 | `assets/fonts/` | Unchanged (HTML previews only) |

Sources: the Kenney packs were downloaded from OpenGameArt's mirrors of Kenney's own pages (https://opengameart.org/content/game-icons, https://opengameart.org/content/game-icons-expansion, https://opengameart.org/content/ui-pack), and each pack's own `license.txt` (CC0) is kept beside the files. CC0 needs no credit; we credit Kenney anyway.

Register the icon packs in a game with `IconCatalog.register(require(Icons.Packs.KenneyGame))` and upload the sheets once (`IconCatalog.configure({ pack = "kenneygame", sheets = { ... } })`).

## Installed into your project on request (not bundled)

| Package | Version | Licence | How | Used by |
|---|---|---|---|---|
| Fusion | `elttob/fusion@0.3.0` | MIT (Daniel P H Fox) | `urk packages --project <dir>` (Wally) | `Integrations/FusionBridge` |
| Promise | `evaera/promise@4.0.0` | MIT (Eryn L. K.) | same | projects that want promises |
| ProfileStore | `lm-loleris/profilestore@1.0.3` (server realm) | Apache-2.0 (loleris) | same, under `[server-dependencies]` | `Integrations/ProfileStoreAdapter` |
| Third-party skills (EL4CTEO, roblox-dev-kit, rbsmithy, roclicks) | pinned commits | MIT | `scripts/install/third_party.py` | see `THIRD_PARTY_NOTICES.md` |

All three Wally packages were resolved and installed with Wally 0.3.2 on 2026-11-08, and a generated project built with Rojo 7.7.1 with them mapped.

## Tools the kit runs but does not ship

| Tool | Licence | Status (2026-11-08) |
|---|---|---|
| Rojo 7.7.1, Wally 0.3.2, Selene 0.32.0, StyLua 2.6.0, Lune 0.11.1 | MPL-2.0 | active; pinned by SHA-256 in CI |
| luau-analyze 0.746, luau-lsp 1.70.1 | MIT | active |
| darklua | MIT | active; not used yet (bundling is not needed for the kit's string requires) |
| Blender 4.2 LTS (CI) / 5.2 (local) | GPL | used to build and verify assets; never redistributed |

## Researched and not integrated

| Resource | Licence | Why not |
|---|---|---|
| Roact | Apache-2.0 | Archived since 2023; React Lua replaces it |
| React Lua (jsdotlua/react-lua) | MIT | Large, and UrkUI plus FusionBridge cover the kit's needs; documented as an option in the UI skills |
| BuiltByBit "Free Icon Pack" | not verifiable | Marketplace terms generally forbid redistribution. Import it locally with `tools/icons/import_pack.py` (writes a `.gitignore`) |
| Commercial UI kits and paid icon packs | proprietary | Never copied. The visual tools compare style, not pixels, and the skills require original art |

## Adding a resource

1. Confirm the licence on the author's own page and keep its text beside the files.
2. CC0, MIT, Apache-2.0, OFL and CC-BY are fine (CC-BY needs visible credit). Non-commercial, "no redistribution" or unknown licences are never committed: import them locally instead.
3. Add a row here and run `python3 urk.py audit --kit`, which flags media without a licence and packs that forbid redistribution.
