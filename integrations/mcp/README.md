# MCP servers

| Server | Purpose | Status in this kit |
|---|---|---|
| Roblox Studio (built in) | Run Luau, read Output, capture the viewport in a live Studio session | Configuration documented. Not exercised: Studio was not installed on the build machine |
| Blender (`ahujasid/mcp-for-blender`) | Drive a live Blender | Exercised in the source project; launcher scripts in `../blender/` |
| `boshyxd/robloxstudio-mcp` (community, MIT) | Fallback Studio MCP with a plugin | Not installed. Review its plugin source before use |
| `Roblox/studio-rust-mcp-server` | Former official standalone server | Archived upstream; prefer the built-in one |

[`mcp.example.json`](mcp.example.json) shows both entries. Copy the parts you need into your project's `.mcp.json`; the installer does this only with `--with-mcp`, merging keys and backing up the old file.

## Roblox Studio

1. Studio: Assistant → Manage MCP Servers → enable Studio as an MCP server (check current Studio docs if menus moved).
2. macOS command: `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`. Windows: `StudioMCP.exe` in the current folder under `%LOCALAPPDATA%\Roblox\Versions\`; this path changes with every Studio update.
3. Or register globally: `claude mcp add Roblox_Studio -- <path to StudioMCP>`.
4. New Claude Code session, then ask Claude to list Studio's tools. Usage and test workflow: the `roblox-studio-mcp` skill.

## Troubleshooting

- Server not listed: servers load at session start; restart Claude Code and approve the project server when asked.
- `ENOENT` on StudioMCP: the Studio path changed after an update; re-point it.
- Blender tools time out: Blender with the add-on is not running, or another process holds port 9876.

Never put API keys in `.mcp.json`. Use environment variables.
