# Skill usage examples

You rarely name a skill. Describe the task; the router and skill descriptions do the rest. These are real outputs of `route.py`.

| You say | Workflow | Skills loaded (direct dependencies included) |
|---|---|---|
| "Create 20 supermarket products" | asset-batch | batch-asset-production, procedural-mesh-generation, uv-texture-atlas, stylized-asset-design, blender-roblox-export, asset-qa-validation, product-packaging-assets, kit-conventions, blender-python-headless |
| "Add a pet inventory with equip slots" | gameplay-system | roblox-architecture, roblox-networking, roblox-security-anti-exploit, roblox-inventory-economy, luau-language |
| "Make a creature with a walk animation" | character | characters-rigging, roblox-animation, blender-roblox-export |
| "The game lags on mobile, optimize it" | optimize | roblox-performance, mesh-optimization-lod |
| "Set up rojo and the Studio MCP" | setup | roblox-toolchain-doctor, roblox-studio-mcp, blender-python-headless |

## Naming a skill directly

"Use the roblox-data-persistence skill to add a migration for version 3" also works, and skips routing.

## Slash commands

| Command | Does |
|---|---|
| `/urk-route <task>` | Plan only: workflow, skills, gates |
| `/urk-doctor` | Environment report |
| `/urk-new-game <template> <Name>` | Scaffold a project |
| `/urk-asset-batch <spec or description>` | Build, QA and stop for approval |
| `/urk-review [path]` | Security and performance review of Luau |
| `/urk-release-check` | Release checklist, no publishing |

## Subagents

Ask "use the urk-qa-reviewer agent to verify this", or let Claude delegate. Each agent file lists the few skills it reads.
