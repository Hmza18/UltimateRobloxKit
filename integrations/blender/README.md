# Blender integration

Two ways to drive Blender, both used in the supermarket project this kit grew from.

| Mode | When | Entry point |
|---|---|---|
| Headless | Repeatable builds, batches, CI | `scripts/blender/build_asset.py`, `verify_export.py` via `scripts/export/asset_batch.py` |
| Live (MCP) | Inspecting scenes, trying a fix interactively | `ahujasid/mcp-for-blender`, pinned commit `2e4b0bc` |

## Live MCP setup (macOS and Linux)

```bash
bash integrations/blender/setup_blender_mcp.sh /path/to/your/project
```

```bash
bash integrations/blender/start_blender_mcp.sh
```

Then add the `blender` entry from [`../mcp/mcp.example.json`](../mcp/mcp.example.json) to the project's `.mcp.json` and start a new Claude Code session (servers load at session start; Claude Code asks you to approve project servers).

Verify end to end, with Blender from `start_blender_mcp.sh` running:

```bash
.urk/blender-mcp/venv/bin/python integrations/blender/test_blender_mcp.py
```

Windows: run the same steps in Git Bash, or create the venv with `py -3.12 -m venv` and point `.mcp.json` at `.urk\blender-mcp\venv\Scripts\mcp-for-blender.exe` with the telemetry variables set in its `env` block.

## Safety notes

- The server has telemetry; the launcher disables it with `DISABLE_TELEMETRY`, `BLENDER_MCP_DISABLE_TELEMETRY` and `MCP_DISABLE_TELEMETRY`.
- `execute_blender_code` runs arbitrary Python inside Blender. Keep the add-on bound to 127.0.0.1 and use the isolated profile so your normal Blender settings are untouched.
- The add-on's optional paid generators and asset downloaders are left off.
- Upstream's `install.sh` and `uvx ... setup` edit global client configs; the kit does not use them.

## Status

Exercised end to end in the source project (2026-11-06, Blender 5.2). The kit's copies of these scripts were adapted from that setup; the headless path was re-run in this repository against Blender 5.2.3.
