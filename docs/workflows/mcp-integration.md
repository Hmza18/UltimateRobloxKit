# MCP integration guide

| Server | Setup | What Claude can do | Verified here |
|---|---|---|---|
| Blender (`mcp-for-blender`, pinned `2e4b0bc`) | `bash integrations/blender/setup_blender_mcp.sh <project>`, then `start_blender_mcp.sh` | Run bpy in a live Blender, read the scene, view the viewport | In the source project (2026-11-06) |
| Roblox Studio (built-in) | Studio → Assistant → Manage MCP Servers → enable; then register `StudioMCP` | Run Luau in Studio, read Output, capture the viewport | No (Studio unavailable) |

## Register

Project-level, shared with your team: `install.py --target <project> --with-mcp` merges both entries into `.mcp.json`. Edit the Studio path on Windows.

Personal: `claude mcp add Roblox_Studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`.

Restart Claude Code. Project servers ask for approval on first use.

## Verify

- Blender: `.urk/blender-mcp/venv/bin/python integrations/blender/test_blender_mcp.py` prints `MCP_E2E PASS`.
- Studio: ask Claude to "list the Studio MCP tools and print the place name". It should call `execute_luau` and return the name.

## Other tools, no MCP needed

Rojo, Wally, Selene, StyLua, luau-lsp and Lune are command-line tools; agents call them through the shell. Open Cloud is an HTTP API; use `rbxcloud` (Sleitnick, MIT) or `curl` with `ROBLOX_API_KEY` from the environment, and only with explicit permission. GitHub uses the `gh` CLI or git.

More detail and troubleshooting: [`integrations/mcp/README.md`](../../integrations/mcp/README.md).
