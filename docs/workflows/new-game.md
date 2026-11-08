# Workflow: a new game

Recipe `new-game` in `catalog/workflows.json`. Ask Claude "build a <genre> game", or follow these steps by hand.

| Step | Skills | Output | Gate |
|---|---|---|---|
| 1. Concept | game-design-core, competitor-research | one-pager, MVP scope (`references/gdd-mvp-template.md`) | The user agrees the scope |
| 2. Scaffold | roblox-architecture, roblox-toolchain-doctor | `new_project.py --template <genre>` | `rokit install`, `rojo build -o build.rbxl` |
| 3. Core loop | genre skill (simulator/tycoon, quests), roblox-networking, roblox-security-anti-exploit | services and controllers | Lune tests for logic, server-side validation for every remote |
| 4. Persistence | roblox-data-persistence | profile schema, migrations | Data survives rejoin in a Studio test (manual) |
| 5. UI | roblox-ui-systems | HUD, shop and settings | Phone, tablet and desktop emulation |
| 6. World and assets | map-world-building, asset-batch workflow | map, props | Performance budget check |
| 7. Monetization | monetization-economy-design | passes and products with fair pricing | Disclosed odds, no dark patterns |
| 8. Test | roblox-testing-debugging, urk-qa-reviewer | test report | All automated checks pass; manual items listed |
| 9. Release | roblox-publishing-liveops, production-management | release checklist | Explicit user permission to publish |

Parallel work: once step 2 exists, steps 3 to 6 can go to separate subagents (`urk-luau-engineer`, `urk-world-builder`, `urk-asset-pipeline`), each given only its own skills.
