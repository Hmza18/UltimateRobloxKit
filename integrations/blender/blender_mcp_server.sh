#!/usr/bin/env bash
# MCP stdio entry point for .mcp.json. Telemetry off, add-on connection local only.
set -euo pipefail
PROJECT="${URK_PROJECT:-$PWD}"
URK_HOME="${URK_HOME:-$PROJECT/.urk/blender-mcp}"
export DISABLE_TELEMETRY=true BLENDER_MCP_DISABLE_TELEMETRY=true MCP_DISABLE_TELEMETRY=true
export BLENDER_HOST=127.0.0.1 BLENDER_PORT="${BLENDER_PORT:-9876}"
exec "$URK_HOME/venv/bin/mcp-for-blender" "$@"
