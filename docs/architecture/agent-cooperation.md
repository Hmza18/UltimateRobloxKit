# Agent cooperation

How the kit's subagents work in parallel without duplicating work or overwriting each other.

## Roles

| Agent | Owns | Reads |
|---|---|---|
| `urk-game-designer` | `PLAN.md` design sections, `docs/design/` | game-design-core, monetization-economy-design |
| `urk-game-architect` | `default.project.json`, `src/shared/Config.luau`, `src/shared/Types.luau`, the Loader, service and controller skeletons | roblox-architecture, roblox-networking |
| `urk-luau-engineer` | the system files assigned in the plan (`src/server/Services/<X>`, `src/shared/Urk/Systems/<X>` copies) | feature skills |
| `urk-ui-designer` | `src/client/UI/`, GUI instances, themes and locales | urk-ui-framework, roblox-icon-design |
| `urk-visuals-director` | client presentation code named in the plan (for example `src/client/Visuals/`): feedback recipes, sequences, theme and quality settings | uvk-visuals-kit, then the uvk-* skill for the task |
| `urk-vfx-engineer` | game-owned VFX preset modules named in its task (for example `src/client/Visuals/Presets/`) | uvk-vfx-presets, uvk-visual-performance |
| `urk-asset-pipeline` | `specs/`, `build/`, `handoff/` | batch-asset-production |
| `urk-world-builder` | map places and kits, `assets/maps/` | map-world-building |
| `urk-test-engineer` | `tests/` | gameplay-testing |
| `urk-performance-optimizer` | the files named in its task only | roblox-performance |
| `urk-qa-reviewer` | nothing (read-only) | kit-conventions |

## Rules

1. **One owner per file.** `roblox-project-planner` writes the ownership table into `PLAN.md`. An agent edits only the files it owns. For changes elsewhere, it adds a request line to `PROGRESS.md` ("needs: Config.SHOP_TAX from architect") and the owner makes the change.
2. **Contracts first.** Shared names (Store paths, action names, remote names, item ids) are agreed in `src/shared/Types.luau` or `Config.luau` by the architect before parallel work starts.
3. **Claim before starting.** Set the task to `doing` with the agent name in `PROGRESS.md`. If a task is already claimed, pick another.
4. **Isolation for big parallel runs.** When the agent environment supports it, give each writer its own git worktree and branch, and merge after review.
5. **Verify independently.** `urk-qa-reviewer` checks the combined result last. Agents never mark their own work approved.
6. **Presentation follows rules.** `urk-visuals-director` and `urk-vfx-engineer` never change gameplay results, never edit the installed library copy (they override presets through the registries), and wait for the server event the plan names. `urk-ui-designer` owns the screens; the visuals agents animate them through `Visuals.UI` and ask for GUI names in `PROGRESS.md`.
7. **Report honestly.** Each agent ends with what it changed, what it ran and the results, and what still needs a person (Studio, devices).
