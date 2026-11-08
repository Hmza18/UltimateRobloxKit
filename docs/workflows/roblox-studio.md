# Roblox Studio workflow

## Code: Rojo

1. In the project: `rokit install`, then `rojo serve`.
2. Studio: open a place, then Plugins → Rojo → Connect. Edit files on disk; Studio updates live.
3. Instances Rojo does not manage (maps, imported meshes) stay in the place file. Keep a `build.rbxl` from `rojo build` for CI, and do map work in a separate place or package.

## Assets

Home → Import 3D → choose the FBX → set units to Studs → Import. Check the MeshPart's `Size` against the spec, front facing `-Z`, and the texture. If the texture is missing, set `TextureID`, or add a SurfaceAppearance.

## AI in Studio: Studio MCP

Enable Studio's built-in MCP server and register it with Claude Code ([MCP integration](mcp-integration.md)). Claude can then run Luau in the edit session, read Output and capture the viewport. See the `roblox-studio-mcp` skill for safe use: local test places only, read before write, undoable changes.

## Playtesting

Use Play (F5) for one client, and Test → Clients and Servers for multiplayer. Use Device emulation for UI. Persistence needs "Enable Studio Access to API Services" in a test experience, never production data.
