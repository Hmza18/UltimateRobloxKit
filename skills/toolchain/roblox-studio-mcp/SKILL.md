---
name: roblox-studio-mcp
description: Drives Roblox Studio through its built-in MCP server - enabling it, registering it with Claude Code, running Luau with execute_luau, reading console output, capturing screenshots, and running real import and scale tests for exported assets in a local test place. Use when the user wants Claude to see or change a Studio session, test models in Studio, or debug in a live place.
license: MIT
metadata:
  category: toolchain
  version: 1.0.0
  triggers: [studio mcp, execute_luau, roblox studio, screen_capture, import test, studio test, playtest in studio]
  depends: [roblox-toolchain-doctor]
---

# Roblox Studio MCP

Recovered from the supermarket project's `roblox-studio-asset-tester` and `roblox-import-validation` skills, generalised.

## Setup (user does the sign-in)

1. Studio installed and signed in by the user. Never install it or sign in without asking.
2. In Studio: Assistant panel → Manage MCP Servers → enable "Studio as MCP server" (menu names can change; check current Studio docs).
3. Register with Claude Code, then restart the session:
   - macOS: `claude mcp add Roblox_Studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`
   - Windows: the `StudioMCP.exe` inside the current Studio version folder under `%LOCALAPPDATA%\Roblox\Versions\` (verify the path on the machine; it changes with each Studio update).
   An example entry is in `$URK/integrations/mcp/mcp.example.json`.
4. Confirm: the session lists tools such as `execute_luau`, `get_console_output`, `screen_capture`. Tool names come from Studio, so read the live list rather than assuming.

## Asset import test workflow

1. Open a **new local place**. Never open or modify the team's live place without explicit permission. Never publish.
2. Import each FBX with Home → Import 3D, units = Studs. No MCP tool imports local mesh files, so the user does this click (or computer use with permission).
3. Generate a checker with `python3 $URK/scripts/export/studio_check.py <batch_out_dir> > StudioCheck.luau` and run its contents with `execute_luau`. It finds each imported `SM_<Asset>` MeshPart, compares `Size` to the spec within 0.01 studs, checks `TextureID`/SurfaceAppearance, and prints one `@@URK_STUDIO@@` JSON line.
4. Read that line with `get_console_output`. Capture the front and three-quarter views with `screen_capture` and look at them.
5. Record results in the batch: append the JSON to `<out>/studio_report.json`. Only a real import plus your inspection makes the Studio check PASS.

## Debugging a live place

`execute_luau` runs in the edit data model. Read state first (`print` paths, attributes), change second, and tell the user what you changed. Prefer small reversible edits; wrap mass edits in `ChangeHistoryService` recordings so the user can undo.

## Pitfalls (from real imports)

- 100× too large: the FBX was exported without `global_scale=0.01`.
- Texture missing after import: the importer may not link the PNG. Upload it or set `TextureID` manually in the test place and report it.
- Front faces the wrong way: Blender front must be -Y; it arrives as Roblox -Z.
- Back faces culled: Roblox draws one side; open meshes show holes.

## Limitations

Studio cannot run in CI and was not available when this kit was built, so every Studio claim in kit docs is a procedure, not a recorded result.
